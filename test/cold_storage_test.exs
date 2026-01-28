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

    test "creates a ColdStorage struct with enabled: false" do
      cs = ColdStorage.new(enabled: false)
      assert cs.enabled == false
    end

    test "defaults enabled to true" do
      cs = ColdStorage.new()
      assert cs.enabled == true
    end
  end

  describe "when disabled" do
    test "put_cache does not write to file", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, enabled: false)

      assert :ok = ColdStorage.put_cache(cs, "key", "value")

      # Should not create directory or file
      refute File.exists?(Path.join(test_dir, "1"))
    end

    test "fetch_cache returns :miss even if file exists", %{test_dir: test_dir} do
      # Setup: write a file using an enabled cache
      cs_enabled = ColdStorage.new(dir: test_dir, vsn: 1)
      ColdStorage.put_cache(cs_enabled, "key", "value")
      assert {:hit, "value"} = ColdStorage.fetch_cache(cs_enabled, "key")

      # Test: try to read it with a disabled cache
      cs_disabled = ColdStorage.new(dir: test_dir, vsn: 1, enabled: false)
      assert :miss = ColdStorage.fetch_cache(cs_disabled, "key")
    end

    test "cached/3 always runs generator", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, enabled: false)

      # First run
      assert "val" == ColdStorage.cached(cs, "key", fn -> {:cache, "val"} end)

      # Second run - should run generator again because it wasn't cached/read
      result =
        ColdStorage.cached(cs, "key", fn ->
          {:cache, "new-val"}
        end)

      assert result == "new-val"
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

    test "generates hash for any valid term" do
      assert is_binary(ColdStorage.filename([{:a, 1, fn -> :ok end}, %{a: 1, b: %{c: self()}}]))
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

    test "caches base value but returns enhanced value with :pcache", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      base_data = %{id: 1, name: "test"}
      enhanced_data = Map.put(base_data, :timestamp, System.system_time())

      result = ColdStorage.cached(cs, "key", fn -> {:pcache, base_data, enhanced_data} end)

      assert result == enhanced_data
      # Verify that base_data was cached, not enhanced_data
      assert {:hit, ^base_data} = ColdStorage.fetch_cache(cs, "key")
    end

    test "returns cached value without generator call after :pcache", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      # First call with :pcache
      ColdStorage.cached(cs, "key", fn -> {:pcache, "cached-value", "returned-value"} end)

      # Second call should return cached value without calling generator
      result =
        ColdStorage.cached(cs, "key", fn ->
          raise "generator should not be called"
        end)

      assert result == "cached-value"
    end

    test ":pcache with complex data structures", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      base = %{users: [%{id: 1}, %{id: 2}]}
      enhanced = %{users: [%{id: 1, active: true}, %{id: 2, active: false}]}

      result = ColdStorage.cached(cs, "users", fn -> {:pcache, base, enhanced} end)

      assert result == enhanced
      assert {:hit, ^base} = ColdStorage.fetch_cache(cs, "users")
    end

    test ":pcache allows different returned value each time after cache", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      # First call: cache base data
      first_timestamp = System.system_time()
      base_data = %{data: "base"}

      ColdStorage.cached(cs, "key", fn ->
        {:pcache, base_data, Map.put(base_data, :ts, first_timestamp)}
      end)

      # Manually verify cache has base data
      assert {:hit, ^base_data} = ColdStorage.fetch_cache(cs, "key")

      # Second call: returns cached base data without enhancement
      result = ColdStorage.cached(cs, "key", fn -> raise "not called" end)
      assert result == base_data
    end

    test ":pcache with nil values", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached(cs, "key", fn -> {:pcache, nil, "returned"} end)

      assert result == "returned"
      assert {:hit, nil} = ColdStorage.fetch_cache(cs, "key")
    end

    test ":pcache caches even if returned value is different type", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result = ColdStorage.cached(cs, "key", fn -> {:pcache, [1, 2, 3], "string"} end)

      assert result == "string"
      assert {:hit, [1, 2, 3]} = ColdStorage.fetch_cache(cs, "key")
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

  describe "with_cache/3 and with_cache/4" do
    test "cache miss + ignore returns value without caching", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result =
        ColdStorage.with_cache(cs, "key", "default", fn val ->
          assert val == "default"
          {:ignore, "returned"}
        end)

      assert result == "returned"
      assert :miss = ColdStorage.fetch_cache(cs, "key")
    end

    test "cache miss + cache stores and returns value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result =
        ColdStorage.with_cache(cs, "key", "default", fn val ->
          assert val == "default"
          {:cache, "cached_value"}
        end)

      assert result == "cached_value"
      assert {:hit, "cached_value"} = ColdStorage.fetch_cache(cs, "key")
    end

    test "cache miss + pcache stores cache_value and returns return_value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result =
        ColdStorage.with_cache(cs, "key", %{}, fn val ->
          assert val == %{}
          {:pcache, %{stored: true}, %{returned: true}}
        end)

      assert result == %{returned: true}
      assert {:hit, %{stored: true}} = ColdStorage.fetch_cache(cs, "key")
    end

    test "cache hit + ignore returns value without modifying cache", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      ColdStorage.put_cache(cs, "key", "original")

      result =
        ColdStorage.with_cache(cs, "key", "default", fn val ->
          assert val == "original"
          {:ignore, "returned"}
        end)

      assert result == "returned"
      assert {:hit, "original"} = ColdStorage.fetch_cache(cs, "key")
    end

    test "cache hit + cache updates and returns value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      ColdStorage.put_cache(cs, "key", "original")

      result =
        ColdStorage.with_cache(cs, "key", "default", fn val ->
          assert val == "original"
          {:cache, "updated"}
        end)

      assert result == "updated"
      assert {:hit, "updated"} = ColdStorage.fetch_cache(cs, "key")
    end

    test "cache hit + pcache updates cache and returns different value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)
      ColdStorage.put_cache(cs, "key", %{count: 1})

      result =
        ColdStorage.with_cache(cs, "key", %{}, fn val ->
          assert val == %{count: 1}
          updated = %{count: 2}
          enhanced = Map.put(updated, :timestamp, :now)
          {:pcache, updated, enhanced}
        end)

      assert result == %{count: 2, timestamp: :now}
      assert {:hit, %{count: 2}} = ColdStorage.fetch_cache(cs, "key")
    end

    test "uses nil as default when not provided", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      result =
        ColdStorage.with_cache(cs, "key", fn val ->
          assert val == nil
          {:cache, "value"}
        end)

      assert result == "value"
    end

    test "with disabled cache, still runs callback but doesn't write", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1, enabled: false)

      # First call with :cache
      result1 =
        ColdStorage.with_cache(cs, "key", "default", fn val ->
          assert val == "default"
          {:cache, "value1"}
        end)

      assert result1 == "value1"

      # Second call should still get default (not cached)
      result2 =
        ColdStorage.with_cache(cs, "key", "default", fn val ->
          assert val == "default"
          {:cache, "value2"}
        end)

      assert result2 == "value2"
      assert :miss = ColdStorage.fetch_cache(cs, "key")
    end

    test "raises on invalid return value", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      assert_raise RuntimeError, ~r/with_cache callback must return/, fn ->
        ColdStorage.with_cache(cs, "key", nil, fn _val ->
          :invalid
        end)
      end
    end

    test "accumulator pattern example", %{test_dir: test_dir} do
      cs = ColdStorage.new(dir: test_dir, vsn: 1)

      # Simulate processing with accumulating query cache
      process = fn items, query_cache ->
        Enum.map_reduce(items, query_cache, fn item, cache ->
          cached_result = Map.get(cache, item)

          if cached_result do
            {cached_result, cache}
          else
            computed = String.upcase(item)
            {computed, Map.put(cache, item, computed)}
          end
        end)
      end

      # First run: nothing cached
      {result1, _} =
        ColdStorage.with_cache(cs, :queries, %{}, fn cache ->
          {results, updated_cache} = process.(["a", "b"], cache)
          {:pcache, updated_cache, {results, updated_cache}}
        end)

      assert result1 == ["A", "B"]
      assert {:hit, %{"a" => "A", "b" => "B"}} = ColdStorage.fetch_cache(cs, :queries)

      # Second run: use cached values and add new ones
      {result2, final_cache} =
        ColdStorage.with_cache(cs, :queries, %{}, fn cache ->
          assert cache == %{"a" => "A", "b" => "B"}
          {results, updated_cache} = process.(["a", "c"], cache)
          {:pcache, updated_cache, {results, updated_cache}}
        end)

      assert result2 == ["A", "C"]
      assert final_cache == %{"a" => "A", "b" => "B", "c" => "C"}
      assert {:hit, ^final_cache} = ColdStorage.fetch_cache(cs, :queries)
    end
  end
end
