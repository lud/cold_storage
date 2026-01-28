# Example: Using with_cache for accumulator pattern
# 
# This shows how the new with_cache/4 function simplifies
# the accumulator pattern for cached state.

defmodule CustomerDataExample do
  # BEFORE: Manual cache fetch and put
  def customer_data_old(%{organization_uuid: uuid} = orga, data_points, cache)
      when is_map(data_points) do
    cache_key = {:query_cache, uuid}

    cached_query_cache =
      case ColdStorage.fetch_cache(cache, cache_key) do
        :miss -> %{}
        {:hit, qc} -> qc
      end

    {results, ctx} = do_customer_data(orga, data_points, cached_query_cache)
    ColdStorage.put_cache(cache, cache_key, ctx.query_cache)

    results
  end

  # AFTER: Using with_cache for cleaner accumulator pattern
  def customer_data_new(%{organization_uuid: uuid} = orga, data_points, cache)
      when is_map(data_points) do
    cache_key = {:query_cache, uuid}

    ColdStorage.with_cache(cache, cache_key, %{}, fn query_cache ->
      {results, ctx} = do_customer_data(orga, data_points, query_cache)
      {:pcache, ctx.query_cache, results}
    end)
  end

  defp do_customer_data(orga, data_points, query_cache) do
    context = %{
      orga: orga,
      inject: %{},
      query_cache: query_cache,
      cognism_client: nil,
      reverse_contact_client: nil
    }

    {results, ctx} =
      Enum.map_reduce(data_points, context, fn {key, mod}, ctx ->
        {result, ctx} = call_customer_data_point(mod, ctx)
        {{key, result}, ctx}
      end)

    {Map.new(results), ctx}
  end

  defp call_customer_data_point(_mod, ctx) do
    # Mock implementation
    {%{data: "result"}, ctx}
  end
end

# Benefits of with_cache:
# 1. No manual cache_key construction repeated
# 2. Automatic handling of :miss vs {:hit, _}
# 3. Clear separation: load -> process -> store decision
# 4. Supports conditional caching with {:cache, _} vs {:ignore, _}
# 5. The {:pcache, cache_value, return_value} pattern explicitly shows
#    what gets cached vs what gets returned
