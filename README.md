# ColdStorage

A simple file-based caching system for Elixir that stores serialized terms on
disk.

**⚠️ Important: This is NOT a production cache solution.** ColdStorage uses the
filesystem directly with no particular optimization, making it slow and
unsuitable for production use. It is specifically designed for scripting,
tooling, or development workflows where simplicity matters more than
performance, and when the Elixir runtime is started multiple times.

## Use Cases

- **API client development** - Cache API responses while writing a scraper or
  API client to avoid spamming endpoints during development.
- **AI** - Save on tokens when writing a prompting or agent client.
- **Build tools** - Cache expensive computations in build scripts or development
  tools
- **Data exploration** - Cache downloaded datasets or API responses during data
  analysis
- **CLI tools** - Persist data between runs of command-line utilities
- **Testing fixtures** - Store expensive-to-generate test data

## Installation

Add `cold_storage` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cold_storage, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
cs = ColdStorage.new()

ColdStorage.cached(cs, "my-key", fn ->
  result = perform_expensive_operation()
  {:cache, result}
end)
```

## Basic Usage

### Creating a Cache Instance

```elixir
# Use defaults (stores in system temp directory with version 1)
cs = ColdStorage.new()

# Specify a custom directory
cs = ColdStorage.new(dir: "/path/to/cache")

# Specify a version (useful for cache invalidation).
# The version will be a sub-directory.
cs = ColdStorage.new(dir: "/tmp/cache", vsn: 2)
cs = ColdStorage.new(dir: "_build/cache", vsn: "my-app-cache-1")
```

### Caching with `cached/3`

The `cached/3` function checks the cache first, and only calls the generator
function if the value is not cached. The generator must return either `{:cache,
value}` to cache the result, or `{:ignore, value}` to return a value without
caching it.

```elixir
cs = ColdStorage.new(vsn: 1)

# This will be cached
user = ColdStorage.cached(cs, "random-user", fn ->
  {:cache, fetch_user_from_api(random_id())}
end)

# Subsequent calls return the cached value without calling the function
^user = ColdStorage.cached(cs, "random-user", fn ->
  {:cache, fetch_user_from_api(random_id())}
end)

# Return a value without caching it
ColdStorage.cached(cs, "temp-data", fn ->
  {:ignore, generate_temporary_data()}
end)
```

### Caching with `cached_ok/3`

The `cached_ok/3` function is a convenience wrapper for functions that return
`{:ok, value}` or error tuples. It automatically caches successful results and
ignores errors.

```elixir
cs = ColdStorage.new(vsn: 1)

# Caches {:ok, _} tuples returned by the generator
ColdStorage.cached_ok(cs, "api-call-1", fn ->
  with {:ok, users} <- HTTPClient.get("/api/users") do
    {:ok, do_something_with(users)}
  end
end)

# Any other value than an {:ok, _} tuple is not cached.
ColdStorage.cached_ok(cs, "failing-endpoint", fn ->
  {:error, :not_found}
end)
```

## Cache Versioning

ColdStorage uses versions to manage cache invalidation. When you change the
version number, all cached data from previous versions becomes inaccessible
(though the files remain on disk).

```elixir
# Version 1 cache
cs_v1 = ColdStorage.new(vsn: 1)

# Version 2 cache
cs_v2 = ColdStorage.new(vsn: 2)
```

You can use anythign as the `vsn` as long as `to_string(vsn)` returns a valid
directory name.

## Direct Cache Operations

For more control, you can use the lower-level cache operations:

```elixir
cs = ColdStorage.new(vsn: 1)

# Store a value
ColdStorage.put_cache(cs, "my-key", %{data: "value"})

# Fetch a value
case ColdStorage.fetch_cache(cs, "my-key") do
  {:hit, value} -> IO.puts("Found: #{inspect(value)}")
  :miss -> IO.puts("Not cached")
end

# Get the file path for a key
path = ColdStorage.path_of(cs, "my-key")

# Get the cache directory (including the vsn segment)
dir = ColdStorage.cache_dir(cs)
```

## How It Works

ColdStorage stores each cached value as a separate file:

1. Each cache key is hashed using SHA-1 to generate a filename
2. Values are serialized using Erlang's `:erlang.term_to_binary/1`
3. Files are stored in `<dir>/<version>/<hash>`

For example:
```text
/tmp/my-cache/
  ├── 1/
  │   ├── A1B2C3D4E5F6...
  │   └── F6E5D4C3B2A1...
  └── 2/
      └── 1234567890AB...
```

**Performance characteristics:**
- Each cache operation performs file I/O
- No in-memory caching or optimization
- Suitable for infrequent access patterns only

## Limitations

- ⚠️ **Slow**: Every operation hits the filesystem with no optimization
- **No TTL**: Cached values never expire automatically
- **No size limits**: The cache can grow unbounded
- **No concurrency control**: Concurrent writes to the same key are managed by
  the operating system as the cache uses direct file operations
- **No automatic cleanup**: Old versions accumulate on disk

These limitations are intentional. ColdStorage prioritizes simplicity and ease
of use for development and tooling scenarios where performance is not critical.


