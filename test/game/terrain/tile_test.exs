defmodule ThistleTea.Game.Terrain.TileTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Terrain.Liquid
  alias ThistleTea.Game.Terrain.Tile

  @grid_size 533.3333333333334

  describe "decode/1" do
    test "rejects incompatible builds, versions, corrupt sizes and nonfinite heights" do
      binary = tile(flat_height(), liquid())
      assert {:ok, %Tile{}} = Tile.decode(binary)
      assert {:error, :invalid_terrain} = Tile.decode(binary_part(binary, 0, byte_size(binary) - 1))
      assert {:error, :invalid_terrain} = Tile.decode(replace(binary, 8, <<1234::little-32>>))
      assert {:error, :invalid_terrain} = Tile.decode(replace(binary, 4, "z1.4"))
      assert {:error, :invalid_terrain} = Tile.decode(replace(binary, 28, <<0xFFFFFFFF::little-32>>))
      assert {:error, :invalid_terrain} = Tile.decode(tile(flat_height(), liquid() <> <<0>>))

      assert {:error, :invalid_terrain} =
               Tile.decode(tile(replace(flat_height(), 8, <<0x7FC00000::little-32>>), liquid()))
    end

    test "accepts dry terrain without retaining unused sections" do
      assert {:ok, nil} = Tile.decode(tile(flat_height(), <<>>))
    end
  end

  describe "coordinates/2" do
    test "keeps world axes and grid boundaries in file order" do
      assert Tile.coordinates(-9500.0, -220.0) == {49, 32}
      assert Tile.coordinates(0.0, 0.0) == {32, 32}
      assert Tile.coordinates(0.001, -0.001) == {31, 32}
      assert Tile.coordinates(-@grid_size, @grid_size) == {33, 31}
    end
  end

  describe "area_bit/2" do
    test "decodes global and per-cell exploration bits separately from area IDs" do
      for area <- [
            <<"AREA", 1::little-16, 894::little-16>>,
            <<"AREA", 0::little-16, 0::little-16>> <> :binary.copy(<<894::little-16>>, 256)
          ] do
        height = flat_height()
        water = liquid()
        area_size = byte_size(area)
        height_offset = 44 + area_size
        liquid_offset = height_offset + byte_size(height)

        binary =
          <<"MAPSz1.5", 5875::little-32, 44::little-32, area_size::little-32, height_offset::little-32,
            byte_size(height)::little-32, liquid_offset::little-32, byte_size(water)::little-32, 0::little-32,
            0::little-32, area::binary, height::binary, water::binary>>

        assert {:ok, tile} = Tile.decode(binary)
        assert Tile.area_bit(tile, {0.0, 0.0, 0.0}) == 894
      end
    end
  end

  describe "sample/2" do
    test "distinguishes high sea and rejects submerged ground and positions below terrain" do
      {:ok, terrain} = Tile.decode(tile(flat_height(-20.0), liquid(0x12, 0.0)))
      assert %Liquid{surface: +0.0, floor: -20.0, flags: 0x12} = column = Tile.sample(terrain, {0.0, 0.0, 50.0})
      assert Liquid.high_sea?(column)
      assert Tile.sample(terrain, {0.0, 0.0, -23.0}) == nil
      {:ok, buried} = Tile.decode(tile(flat_height(2.0), liquid(0x12, 0.0)))
      assert Tile.sample(buried, {0.0, 0.0, 10.0}) == nil
      refute Liquid.high_sea?(%{column | flags: 0x02})
      refute Liquid.high_sea?(nil)
    end

    test "reads per-cell flags and cropped liquid height grids without transposing axes" do
      types = :binary.copy(<<0>>, 256) |> replace(17, <<0x12>>)
      entries = :binary.copy(<<0>>, 512)
      heights = <<10.0::little-float-32, 20.0::little-float-32, 30.0::little-float-32, 40.0::little-float-32>>

      liquid =
        <<"MLIQ", 0::little-16, 0::little-16, 9, 8, 2, 2, 0.0::little-float-32, entries::binary, types::binary,
          heights::binary>>

      {:ok, terrain} = Tile.decode(tile(flat_height(), liquid))

      assert %Liquid{surface: 20.0} = Tile.sample(terrain, position(8.25, 10.25))
      assert %Liquid{surface: 30.0} = Tile.sample(terrain, position(9.25, 9.25))
      assert Tile.sample(terrain, position(8.25, 8.25)) == nil
      assert Tile.sample(terrain, position(10.25, 9.25)) == nil
      assert Tile.sample(terrain, position(0.25, 0.25)) == nil
    end

    test "interpolates each terrain triangle for float and compact height encodings" do
      for encoding <- [:float, :int16, :int8] do
        {:ok, terrain} = Tile.decode(tile(height_map(encoding), liquid(0x12, 100.0)))

        for {x, y, expected} <- [{0.75, 0.1, 19.3}, {0.1, 0.75, 25.8}, {0.9, 0.75, 33.8}, {0.75, 0.9, 35.3}] do
          assert_in_delta Tile.sample(terrain, position(x, y)).floor, expected, 0.0001
        end
      end
    end

    test "terrain holes do not hide liquid beneath the missing floor" do
      holes = <<1::little-16>> <> :binary.copy(<<0>>, 510)
      {:ok, terrain} = Tile.decode(tile(height_map(:float), liquid(0x12, 0.0), holes))
      assert %Liquid{floor: -100_000.0} = Tile.sample(terrain, position(0.25, 0.25))
    end
  end

  defp position(row, column), do: {-row * @grid_size / 128, -column * @grid_size / 128, 100.0}

  defp flat_height(level \\ -20.0), do: <<"MHGT", 1::little-32, level::little-float-32, level::little-float-32>>

  defp liquid(type \\ 0x12, level \\ 0.0),
    do: <<"MLIQ", 3::little-16, type::little-16, 0, 0, 129, 129, level::little-float-32>>

  defp height_map(encoding) do
    {flags, maximum} =
      case encoding do
        :float -> {0, 100.0}
        :int16 -> {2, 65_535.0}
        :int8 -> {4, 255.0}
      end

    values = %{0 => 10, 129 => 20, 1 => 30, 130 => 40, 16_641 => 24}
    data = for index <- 0..33_024, into: <<>>, do: encode(Map.get(values, index, 0), encoding)
    <<"MHGT", flags::little-32, 0.0::little-float-32, maximum::little-float-32, data::binary>>
  end

  defp encode(value, :float), do: <<value * 1.0::little-float-32>>
  defp encode(value, :int16), do: <<value::little-16>>
  defp encode(value, :int8), do: <<value>>

  defp tile(height, liquid, holes \\ :binary.copy(<<0>>, 512)) do
    liquid_offset = if liquid == <<>>, do: 0, else: 44 + byte_size(height)
    holes_offset = 44 + byte_size(height) + byte_size(liquid)

    <<"MAPSz1.5", 5875::little-32, 0::little-32, 0::little-32, 44::little-32, byte_size(height)::little-32,
      liquid_offset::little-32, byte_size(liquid)::little-32, holes_offset::little-32, byte_size(holes)::little-32,
      height::binary, liquid::binary, holes::binary>>
  end

  defp replace(binary, offset, value) do
    size = byte_size(value)
    <<before::binary-size(^offset), _old::binary-size(^size), after_data::binary>> = binary
    before <> value <> after_data
  end
end
