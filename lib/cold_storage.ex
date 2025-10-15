defmodule ColdStorage do
  @moduledoc """
  A simple file-based caching system that stores serialized Elixir terms.

  This cache mechanism using files is slow and is intended for scripting and
  tooling, not for a generic cache in production. The original use case was to
  cache responses from an API while writing a client.

  `ColdStorage` provides a versioned cache storage mechanism that saves data to
  the filesystem. Each cache instance has a directory and version, allowing for
  cache invalidation by changing the version number.



  ## Examples

      iex> cs = ColdStorage.new(dir: "/tmp/my-cache", vsn: 1)
      iex> ColdStorage.cached(cs, "my-key", fn -> {:cache, "my-value"} end)
      "my-value"

  """

  @enforce_keys [:dir, :vsn]
  defstruct @enforce_keys

  @doc """
  Creates a new ColdStorage configuration.

  Configurations are simple data structures, there is no process holding a
  connection. Each cache call will directly hit the file system.

  ## Options

    * `:dir` - The base directory for cache storage. Defaults to a
      "cold-storage" subdirectory in the system temporary directory.
    * `:vsn` - The cache version appended to cache paths as a path segment.
      Accepts anything that returns a valid unix directory name when given to
      `Kernel.to_string/1`. Defaults to `1`.

  ## Examples

      iex> ColdStorage.new()
      %ColdStorage{dir: "/tmp/cold-storage", vsn: 1}

      iex> ColdStorage.new(dir: "/var/cache", vsn: "my-cache-1")
      %ColdStorage{dir: "/var/cache", vsn: "my-cache-1"}

  """
  def new(opts \\ []) do
    dir = Keyword.get_lazy(opts, :dir, &default_dir/0)
    vsn = Keyword.get(opts, :vsn, 1)
    %__MODULE__{dir: dir, vsn: vsn}
  end

  defp default_dir do
    Path.join(System.tmp_dir!(), "cold-storage")
  end

  @doc """
  Generates a cache filename from a key.

  Creates a deterministic filename by hashing the key with SHA and encoding
  it as a hexadecimal string.

  ## Examples

      iex> ColdStorage.filename("my-key")
      "61BA747FE2F5B3D513C40550084C6284FBBC1094"

  """
  def filename(key), do: Base.encode16(:crypto.hash(:sha, key))

  @doc """
  Retrieves a cached value or generates and caches it if not present.

  The generator function must return either `{:cache, value}` to cache the
  result, or `{:ignore, value}` to return the value without caching it.

  ## Parameters

    * `cs` - The ColdStorage instance
    * `key` - The cache key (any term)
    * `generator` - A zero-arity function that generates the value if not cached

  ## Example

      cs = ColdStorage.new(vsn: "cs-test")

      ColdStorage.cached(cs, "expensive-key", fn ->
        {:cache, perform_expensive_computation()}
      end)

      ColdStorage.cached(cs, "skip-cache", fn ->
        {:ignore, temporary_value()}
      end)

  """
  def cached(cs, key, generator) do
    case fetch_cache(cs, key) do
      :miss ->
        case generator.() do
          {:cache, value} ->
            put_cache(cs, key, value)
            value

          {:ignore, value} ->
            value

          other ->
            raise "cache generator must return either {:cache, value} or {:ignore, value}, got: #{inspect(other)}"
        end

      {:hit, value} ->
        value
    end
  end

  @doc """
  Convenience function for caching results from functions that return `{:ok, value}`.

  Caches any return value that is an ok tuple and ignores the rest.

  ## Parameters

    * `cs` - The ColdStorage instance
    * `key` - The cache key (any term)
    * `generator` - A zero-arity function that returns `{:ok, value}` or an error tuple

  ## Examples

      iex> cs = ColdStorage.new(vsn: "cs-test")
      iex> ColdStorage.cached_ok(cs, "my-call", fn -> {:error, :foo} end)
      iex> ColdStorage.cached_ok(cs, "my-call", fn -> {:ok, 1} end)
      iex> ColdStorage.cached_ok(cs, "my-call", fn -> raise "not called" end)
      {:ok, 1}

  """
  def cached_ok(cs, key, generator) do
    cached(cs, key, fn ->
      case generator.() do
        {:ok, value} -> {:cache, {:ok, value}}
        other -> {:ignore, other}
      end
    end)
  end

  @doc """
  Fetches a value from the cache.

  Returns `{:hit, value}` if the value is found in the cache, or `:miss` if not.
  Raises an error if the cache file cannot be read (except for `:enoent`).

  ## Parameters

    * `cs` - The ColdStorage instance
    * `key` - The cache key (any term)

  ## Returns

    * `{:hit, value}` - The cached value was found
    * `:miss` - The value was not found in the cache

  ## Examples

      iex> cs = ColdStorage.new(vsn: "cs-test")
      iex> ColdStorage.fetch_cache(cs, "nonexistent")
      :miss

      iex> cs = ColdStorage.new(vsn: "cs-test")
      iex> ColdStorage.put_cache(cs, "my-key", "my-value")
      iex> ColdStorage.fetch_cache(cs, "my-key")
      {:hit, "my-value"}

  """
  def fetch_cache(cs, key) do
    path = path_of(cs, key)

    case File.read(path) do
      {:ok, bin} -> deserialize_cache(bin)
      {:error, :enoent} -> :miss
      {:error, e} -> raise "could not read from cache: #{inspect(e)}"
    end
  end

  @doc """
  Stores a value in the cache.

  Creates the cache directory if it doesn't exist and writes the serialized
  value to the cache file.

  ## Parameters

    * `cs` - The ColdStorage instance
    * `key` - The cache key (any term)
    * `value` - The value to cache (any term)

  ## Examples

      iex> cs = ColdStorage.new(vsn: "cs-test")
      iex> ColdStorage.put_cache(cs, "my-key", %{data: "value"})
      :ok

  """
  def put_cache(cs, key, value) do
    path = path_of(cs, key)
    File.mkdir_p!(Path.dirname(path))

    :ok = File.write!(path, serialize_cache(value))
  end

  @doc """
  Returns the full file path for a given cache key.

  ## Parameters

    * `cs` - The ColdStorage instance
    * `key` - The cache key (any term)

  ## Examples

      iex> cs = ColdStorage.new(dir: "/tmp/cache", vsn: 1)
      iex> ColdStorage.path_of(cs, "my-key")
      "/tmp/cache/1/61BA747FE2F5B3D513C40550084C6284FBBC1094"

  """
  def path_of(cs, key) do
    Path.join(cache_dir(cs), filename(key))
  end

  @doc """
  Returns the cache directory path for the given ColdStorage instance.

  The cache directory is a combination of the base directory and the version number.

  ## Parameters

    * `cs` - The ColdStorage instance

  ## Examples

      iex> cs = ColdStorage.new(dir: "/tmp/cache", vsn: 2)
      iex> ColdStorage.cache_dir(cs)
      "/tmp/cache/2"

  """
  def cache_dir(%__MODULE__{} = cs) do
    Path.join(cs.dir, to_string(cs.vsn))
  end

  defp deserialize_cache(bin) do
    {:hit, :erlang.binary_to_term(bin)}
  rescue
    _ in ArgumentError -> :miss
  end

  defp serialize_cache(value) do
    :erlang.term_to_binary(value)
  end
end
