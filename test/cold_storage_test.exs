defmodule ColdStorageTest do
  use ExUnit.Case
  doctest ColdStorage

  setup do
    {:ok, test_dir} = Briefly.create(type: :directory)
    {:ok, test_dir: test_dir}
  end

  describe "new/1" do
    test "creates a ColdStorage struct with default options" do
      cs = ColdStorage.new()
      assert %ColdStorage{} = cs
      assert cs.dir == Path.join(System.tmp_dir!(), "cold-storage")
      assert cs.vsn == 1
    end

    test "creates a ColdStorage struct with custom dir", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir)
      assert cs.dir == test_dir
      assert cs.vsn == 1
    end

    test "creates a ColdStorage struct with custom vsn", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: "v2")
      assert cs.vsn == "v2"
    end

    test "creates a ColdStorage struct with custom dir and vsn", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 42)
      assert cs.dir == test_dir
      assert cs.vsn == 42
    end
  end

  describe "filename/1" do
    test "generates consistent filenames for the same key" do
      filename1 = ColdStorage.filename("test-key")
      filename2 = ColdStorage.filename("test-key")
      assert filename1 == filename2
    end

    test "generates different filenames for different keys" do
      filename1 = ColdStorage.filename("key1")
      filename2 = ColdStorage.filename("key2")
      assert filename1 != filename2
    end

    test "generates uppercase hex string" do
      filename = ColdStorage.filename("test")
      assert filename == String.upcase(filename)
      assert String.match?(filename, ~r/^[0-9A-F]+$/)
    end

    test "generates SHA hash of the correct length" do
      filename = ColdStorage.filename("test")
      # SHA-1 produces 40 hex characters (160 bits / 4 bits per hex char)
      assert String.length(filename) == 40
    end
  end

  describe "cache_dir/1" do
    test "returns the cache directory path", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      assert ColdStorage.cache_dir(cs) == Path.join(test_dir, "1")
    end

    test "converts vsn to string", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 123)
      assert ColdStorage.cache_dir(cs) == Path.join(test_dir, "123")
    end

    test "handles string vsn", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: "version-2")
      assert ColdStorage.cache_dir(cs) == Path.join(test_dir, "version-2")
    end
  end

  describe "path_of/2" do
    test "returns the full path for a cache key", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      path = ColdStorage.path_of(cs, "my-key")

      expected_filename = ColdStorage.filename("my-key")
      expected_path = Path.join([test_dir, "1", expected_filename])

      assert path == expected_path
    end

    test "generates different paths for different keys", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      path1 = ColdStorage.path_of(cs, "key1")
      path2 = ColdStorage.path_of(cs, "key2")

      assert path1 != path2
    end

    test "generates different paths for different versions", %{test_dir: test_dir} do
      cs1 = ColdStorage.new(dir: test_dir, vsn: 1)
      cs2 = ColdStorage.new(dir: test_dir, vsn: 2)

      path1 = ColdStorage.path_of(cs1, "key")
      path2 = ColdStorage.path_of(cs2, "key")

      assert path1 != path2
    end
  end

  describe "put_cache/3 and fetch_cache/2" do
    test "stores and retrieves a simple value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      ColdStorage.put_cache(cs, "test-key", "test-value")
      assert {:hit, "test-value"} = ColdStorage.fetch_cache(cs, "test-key")
    end

    test "returns :miss for non-existent key", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      assert :miss = ColdStorage.fetch_cache(cs, "nonexistent")
    end

    test "stores and retrieves complex data structures", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      complex_data = %{
        list: [1, 2, 3],
        tuple: {:ok, "value"},
        map: %{nested: %{data: "here"}},
        atom: :test_atom
      }

      ColdStorage.put_cache(cs, "complex", complex_data)
      assert {:hit, ^complex_data} = ColdStorage.fetch_cache(cs, "complex")
    end

    test "creates cache directory if it doesn't exist", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      cache_dir = ColdStorage.cache_dir(cs)

      refute File.exists?(cache_dir)

      ColdStorage.put_cache(cs, "test-key", "value")

      assert File.exists?(cache_dir)
      assert File.dir?(cache_dir)
    end

    test "overwrites existing cache value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      ColdStorage.put_cache(cs, "key", "value1")
      assert {:hit, "value1"} = ColdStorage.fetch_cache(cs, "key")

      ColdStorage.put_cache(cs, "key", "value2")
      assert {:hit, "value2"} = ColdStorage.fetch_cache(cs, "key")
    end

    test "cache is isolated by version", %{test_dir: test_dir} do
      cs1 = ColdStorage.new(dir: test_dir, vsn: 1)
      cs2 = ColdStorage.new(dir: test_dir, vsn: 2)

      ColdStorage.put_cache(cs1, "key", "value-v1")
      ColdStorage.put_cache(cs2, "key", "value-v2")

      assert {:hit, "value-v1"} = ColdStorage.fetch_cache(cs1, "key")
      assert {:hit, "value-v2"} = ColdStorage.fetch_cache(cs2, "key")
    end

    test "returns :miss for corrupted cache file", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      path = ColdStorage.path_of(cs, "corrupted")

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "not a valid erlang term")

      assert :miss = ColdStorage.fetch_cache(cs, "corrupted")
    end
  end

  describe "cached/3" do
    test "calls generator and caches result when cache is empty", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached(cs, "key", fn -> {:cache, "computed-value"} end)

      assert result == "computed-value"
      assert {:hit, "computed-value"} = ColdStorage.fetch_cache(cs, "key")
    end

    test "returns cached value without calling generator", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      # First call caches the value
      ColdStorage.cached(cs, "key", fn -> {:cache, "value1"} end)

      # Second call should return cached value without calling generator
      result =
        ColdStorage.cached(cs, "key", fn ->
          raise "generator should not be called"
        end)

      assert result == "value1"
    end

    test "does not cache when generator returns :ignore", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached(cs, "key", fn -> {:ignore, "not-cached"} end)

      assert result == "not-cached"
      assert :miss = ColdStorage.fetch_cache(cs, "key")
    end

    test "raises when generator returns invalid format", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      assert_raise RuntimeError, ~r/cache generator must return/, fn ->
        ColdStorage.cached(cs, "key", fn -> "invalid-format" end)
      end
    end

    test "generator is called each time when returning :ignore", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      test_pid = self()

      call_count = fn ->
        send(test_pid, :generator_called)
        {:ignore, "value"}
      end

      ColdStorage.cached(cs, "key", call_count)
      assert_received :generator_called

      ColdStorage.cached(cs, "key", call_count)
      assert_received :generator_called
    end

    test "caches complex terms", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      complex_result = %{data: [1, 2, 3], status: :ok}

      result =
        ColdStorage.cached(cs, "complex", fn ->
          {:cache, complex_result}
        end)

      assert result == complex_result

      # Verify it's actually cached
      cached_result =
        ColdStorage.cached(cs, "complex", fn ->
          raise "should not be called"
        end)

      assert cached_result == complex_result
    end
  end

  describe "cached_ok/3" do
    test "caches {:ok, value} tuples", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached_ok(cs, "key", fn -> {:ok, "value"} end)

      assert result == {:ok, "value"}
      assert {:hit, {:ok, "value"}} = ColdStorage.fetch_cache(cs, "key")
    end

    test "does not cache error tuples", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached_ok(cs, "key", fn -> {:error, :reason} end)

      assert result == {:error, :reason}
      assert :miss = ColdStorage.fetch_cache(cs, "key")
    end

    test "returns cached {:ok, value} without calling generator", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      # First call caches the value
      ColdStorage.cached_ok(cs, "key", fn -> {:ok, "cached"} end)

      # Second call should return cached value
      result =
        ColdStorage.cached_ok(cs, "key", fn ->
          raise "generator should not be called"
        end)

      assert result == {:ok, "cached"}
    end

    test "calls generator each time for non-ok results", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      test_pid = self()

      generator = fn ->
        send(test_pid, :called)
        {:error, :test}
      end

      ColdStorage.cached_ok(cs, "key", generator)
      assert_received :called

      ColdStorage.cached_ok(cs, "key", generator)
      assert_received :called
    end

    test "does not cache other return values", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached_ok(cs, "key", fn -> :other_value end)

      assert result == :other_value
      assert :miss = ColdStorage.fetch_cache(cs, "key")
    end

    test "works with complex ok values", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      complex_data = %{users: [%{id: 1, name: "Alice"}], total: 1}
      result = ColdStorage.cached_ok(cs, "api-call", fn -> {:ok, complex_data} end)

      assert result == {:ok, complex_data}

      # Verify caching
      cached_result =
        ColdStorage.cached_ok(cs, "api-call", fn ->
          raise "should not be called"
        end)

      assert cached_result == {:ok, complex_data}
    end
  end

  describe "version isolation" do
    test "changing version invalidates cache", %{test_dir: test_dir} do
      cs_v1 = ColdStorage.new(dir: test_dir, vsn: 1)
      cs_v2 = ColdStorage.new(dir: test_dir, vsn: 2)

      ColdStorage.put_cache(cs_v1, "key", "v1-value")

      # Same key but different version should miss
      assert :miss = ColdStorage.fetch_cache(cs_v2, "key")
    end

    test "multiple versions can coexist", %{test_dir: test_dir} do
      cs_v1 = ColdStorage.new(dir: test_dir, vsn: 1)
      cs_v2 = ColdStorage.new(dir: test_dir, vsn: 2)
      cs_v3 = ColdStorage.new(dir: test_dir, vsn: 3)

      ColdStorage.put_cache(cs_v1, "key", "value1")
      ColdStorage.put_cache(cs_v2, "key", "value2")
      ColdStorage.put_cache(cs_v3, "key", "value3")

      assert {:hit, "value1"} = ColdStorage.fetch_cache(cs_v1, "key")
      assert {:hit, "value2"} = ColdStorage.fetch_cache(cs_v2, "key")
      assert {:hit, "value3"} = ColdStorage.fetch_cache(cs_v3, "key")
    end
  end

  describe "edge cases" do
    test "handles empty string as key", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      ColdStorage.put_cache(cs, "", "empty-key-value")
      assert {:hit, "empty-key-value"} = ColdStorage.fetch_cache(cs, "")
    end

    test "handles nil as value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      ColdStorage.put_cache(cs, "nil-key", nil)
      assert {:hit, nil} = ColdStorage.fetch_cache(cs, "nil-key")
    end

    test "handles binary data", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      binary_data = <<0, 1, 2, 3, 255>>

      ColdStorage.put_cache(cs, "binary", binary_data)
      assert {:hit, ^binary_data} = ColdStorage.fetch_cache(cs, "binary")
    end

    test "handles very long keys", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      long_key = String.duplicate("a", 10_000)

      ColdStorage.put_cache(cs, long_key, "value")
      assert {:hit, "value"} = ColdStorage.fetch_cache(cs, long_key)
    end

    test "handles large values", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      large_value = List.duplicate("data", 10_000)

      ColdStorage.put_cache(cs, "large", large_value)
      assert {:hit, ^large_value} = ColdStorage.fetch_cache(cs, "large")
    end
  end
end
