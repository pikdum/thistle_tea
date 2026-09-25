defmodule ThistleTea.Native.NamigatorConcurrencyTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Native.Namigator

  @moduletag :namigator_maps

  @queries [
    {0, {-8949.95, -132.49, 83.53}, {-8955.0, -140.0, 84.0}},
    {36, {-131.290833, -591.243103, 18.077190}, {-115.263672, -617.396118, 13.579387}}
  ]

  describe "concurrent queries" do
    test "preserves paths and geometry while workers switch maps" do
      expected =
        Map.new(@queries, fn {map, {sx, sy, _sz}, {gx, gy, _gz}} = query ->
          Namigator.load_adt_at(map, sx, sy)
          Namigator.load_adt_at(map, gx, gy)
          assert [_ | _] = path(query, true)
          {query, observation(query)}
        end)

      results =
        1..24
        |> Task.async_stream(
          fn _ ->
            for _ <- 1..20, query <- @queries do
              assert observation(query) == Map.fetch!(expected, query)
            end
          end,
          max_concurrency: 24,
          timeout: 30_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "keeps queries safe across ADT unload and reload" do
      {map, {x, y, _}, _} = query = hd(@queries)
      {adt_x, adt_y} = Namigator.load_adt_at(map, x, y)
      assert [_ | _] = expected = path(query, true)
      assert {_, _, _} = expected_hit = walk_hit(query)
      assert outdoors(query) == true

      on_exit(fn -> Namigator.load_adt_at(map, x, y) end)

      readers =
        for _ <- 1..12 do
          Task.async(fn ->
            for _ <- 1..200 do
              result = path(query, true)
              assert is_nil(result) or result == expected
              hit = walk_hit(query)
              assert is_nil(hit) or hit == expected_hit
              assert outdoors(query) in [nil, true]
            end
          end)
        end

      for _ <- 1..4 do
        assert Namigator.unload_adt(map, trunc(adt_x), trunc(adt_y))
        assert is_nil(path(query, true))
        assert is_nil(walk_hit(query))
        assert is_nil(outdoors(query))
        assert {^adt_x, ^adt_y} = Namigator.load_adt_at(map, x, y)
      end

      Task.await_many(readers, 30_000)
      assert path(query, true) == expected
    end
  end

  defp path({map, {sx, sy, sz}, {gx, gy, gz}}, steep) do
    Namigator.find_path(map, sx, sy, sz, gx, gy, gz, steep)
  end

  defp walk_hit({map, {sx, sy, sz}, {gx, gy, gz}}) do
    Namigator.walk_hit_position(map, sx, sy, sz, gx, gy, gz)
  end

  defp outdoors({map, {x, y, z}, _destination}), do: Namigator.outdoors(map, x, y, z)

  defp observation({map, {sx, sy, sz}, {gx, gy, gz}} = query) do
    point = Namigator.find_random_point_around_circle(map, sx, sy, sz, 2.0)
    assert is_nil(point) or match?({x, y, z} when is_float(x) and is_float(y) and is_float(z), point)

    {
      path(query, false),
      path(query, true),
      Namigator.find_heights(map, sx, sy),
      Namigator.get_zone_and_area(map, sx, sy, sz),
      outdoors(query),
      Namigator.query_liquid_surface(map, sx, sy, sz),
      Namigator.line_of_sight(map, sx, sy, sz, gx, gy, gz),
      walk_hit(query),
      Namigator.find_point_between_points(map, sx, sy, sz, gx, gy, gz, 1.0)
    }
  end
end
