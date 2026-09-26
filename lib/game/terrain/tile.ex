defmodule ThistleTea.Game.Terrain.Tile do
  @moduledoc "Decodes build-5875 MaNGOS z1.5 terrain tiles and samples their liquid columns without side effects."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Terrain.Liquid

  defstruct [:area, :height, :liquid, :holes]

  @grid_size 533.3333333333334
  @corners 129 * 129
  @centers 128 * 128

  def coordinates(x, y) when is_number(x) and is_number(y) do
    {floor(32 - x / @grid_size), floor(32 - y / @grid_size)}
  end

  def decode(
        <<"MAPSz1.5", 5875::little-32, area_offset::little-32, area_size::little-32, height_offset::little-32,
          height_size::little-32, liquid_offset::little-32, liquid_size::little-32, holes_offset::little-32,
          holes_size::little-32, _rest::binary>> = binary
      ) do
    with {:ok, liquid_data} <- section(binary, liquid_offset, liquid_size),
         {:ok, liquid} <- decode_liquid(liquid_data),
         {:ok, area_data} <- section(binary, area_offset, area_size),
         {:ok, area} <- decode_area(area_data),
         {:ok, height_data} <- section(binary, height_offset, height_size),
         {:ok, height} <- decode_height(height_data),
         {:ok, holes} <- section(binary, holes_offset, holes_size),
         true <- byte_size(holes) in [0, 512] do
      {:ok, %__MODULE__{area: area, height: height, liquid: liquid, holes: holes}}
    else
      :empty -> {:ok, nil}
      _invalid -> {:error, :invalid_terrain}
    end
  end

  def decode(_binary), do: {:error, :invalid_terrain}

  def sample(%__MODULE__{liquid: liquid} = tile, {x, y, z}) do
    {row, row_fraction} = cell(x)
    {column, column_fraction} = cell(y)
    flags = liquid_flags(liquid, row, column)
    surface = liquid_height(liquid, row, column)
    ground = ground_height(tile, row, column, row_fraction, column_fraction)

    if flags != 0 and is_number(surface) and surface >= ground and z >= ground - 2 do
      %Liquid{flags: flags, surface: surface, floor: ground}
    end
  end

  def sample(_tile, _position), do: nil

  def area_bit(%__MODULE__{area: area}, {x, y, _z}) when is_binary(area) do
    {row, _fraction} = cell(x)
    {column, _fraction} = cell(y)
    <<id::little-16>> = binary_part(area, (div(row, 8) * 16 + div(column, 8)) * 2, 2)
    id
  end

  def area_bit(%__MODULE__{area: area}, _position), do: area

  defp decode_area(<<>>), do: {:ok, nil}
  defp decode_area(<<"AREA", 1::little-16, id::little-16>>), do: {:ok, id}
  defp decode_area(<<"AREA", 0::little-16, _id::little-16, areas::binary-size(512)>>), do: {:ok, areas}
  defp decode_area(_data), do: :error

  defp section(_binary, 0, 0), do: {:ok, <<>>}

  defp section(binary, offset, size) when offset >= 44 and size > 0 and offset + size <= byte_size(binary),
    do: {:ok, :binary.copy(binary_part(binary, offset, size))}

  defp section(_binary, _offset, _size), do: :error

  defp decode_height(<<"MHGT", flags::little-32, base::little-float-32, maximum::little-float-32, data::binary>>)
       when flags in [0, 1, 2, 4] and maximum >= base do
    {encoding, bytes, multiplier} = height_encoding(flags, base, maximum)

    if byte_size(data) == bytes * (@corners + @centers) and (encoding != :float or valid_floats?(data)) do
      {:ok, %{encoding: encoding, base: base, multiplier: multiplier, data: data}}
    else
      :error
    end
  end

  defp decode_height(_data), do: :error

  defp height_encoding(0, _base, _maximum), do: {:float, 4, 1.0}
  defp height_encoding(1, _base, _maximum), do: {:flat, 0, 0.0}
  defp height_encoding(2, base, maximum), do: {:int16, 2, (maximum - base) / 65_535}
  defp height_encoding(4, base, maximum), do: {:int8, 1, (maximum - base) / 255}

  defp decode_liquid(<<>>), do: :empty

  defp decode_liquid(
         <<"MLIQ", flags::little-16, type::little-16, offset_x, offset_y, width, height, level::little-float-32,
           data::binary>>
       )
       when flags in 0..3 and width > 0 and height > 0 and offset_x + width <= 129 and offset_y + height <= 129 do
    with {:ok, types, heights} <- liquid_data(data, flags, width, height) do
      {:ok,
       %{
         type: type,
         types: types,
         heights: heights,
         offset_x: offset_x,
         offset_y: offset_y,
         width: width,
         height: height,
         level: level
       }}
    end
  end

  defp decode_liquid(_data), do: :error

  defp liquid_data(data, flags, width, height) do
    type_size = if (flags &&& 1) == 0, do: 768, else: 0
    height_size = if (flags &&& 2) == 0, do: width * height * 4, else: 0

    if byte_size(data) == type_size + height_size and valid_floats?(binary_part(data, type_size, height_size)) do
      <<types::binary-size(^type_size), heights::binary>> = data
      types = if type_size != 0, do: binary_part(types, 512, 256)
      {:ok, types, heights}
    else
      :error
    end
  end

  defp cell(coordinate) do
    value = 128 * (32 - coordinate / @grid_size)
    integer = floor(value)
    {integer &&& 127, value - integer}
  end

  defp liquid_flags(%{types: nil, type: type}, _row, _column), do: type
  defp liquid_flags(%{types: types}, row, column), do: :binary.at(types, div(row, 8) * 16 + div(column, 8))

  defp liquid_height(liquid, row, column) do
    row = row - liquid.offset_y
    column = column - liquid.offset_x

    if row >= 0 and row < liquid.height and column >= 0 and column < liquid.width do
      case liquid.heights do
        <<>> -> liquid.level
        heights -> float_at(heights, row * liquid.width + column)
      end
    end
  end

  defp ground_height(%__MODULE__{height: %{encoding: :flat, base: base}}, _row, _column, _x, _y), do: base

  defp ground_height(%__MODULE__{height: height, holes: holes}, row, column, x, y) do
    if hole?(holes, row, column) do
      -100_000.0
    else
      h1 = height_at(height, row * 129 + column)
      h2 = height_at(height, (row + 1) * 129 + column)
      h3 = height_at(height, row * 129 + column + 1)
      h4 = height_at(height, (row + 1) * 129 + column + 1)
      center = 2 * height_at(height, @corners + row * 128 + column)
      interpolate({h1, h2, h3, h4, center}, x, y)
    end
  end

  defp hole?(<<>>, _row, _column), do: false

  defp hole?(holes, row, column) do
    <<bits::little-16>> = binary_part(holes, (div(row, 8) * 16 + div(column, 8)) * 2, 2)
    bit = div(rem(row, 8), 2) * 4 + div(rem(column, 8), 2)
    (bits &&& 1 <<< bit) != 0
  end

  defp interpolate({h1, h2, _h3, _h4, center}, x, y) when x + y < 1 and x > y,
    do: (h2 - h1) * x + (center - h1 - h2) * y + h1

  defp interpolate({h1, _h2, h3, _h4, center}, x, y) when x + y < 1, do: (center - h1 - h3) * x + (h3 - h1) * y + h1

  defp interpolate({_h1, h2, _h3, h4, center}, x, y) when x > y,
    do: (h2 + h4 - center) * x + (h4 - h2) * y + center - h4

  defp interpolate({_h1, _h2, h3, h4, center}, x, y), do: (h4 - h3) * x + (h3 + h4 - center) * y + center - h4

  defp height_at(%{encoding: :float, data: data}, index), do: float_at(data, index)

  defp height_at(%{encoding: :int16, data: data, base: base, multiplier: multiplier}, index) do
    <<value::little-16>> = binary_part(data, index * 2, 2)
    base + value * multiplier
  end

  defp height_at(%{encoding: :int8, data: data, base: base, multiplier: multiplier}, index),
    do: base + :binary.at(data, index) * multiplier

  defp float_at(data, index) do
    <<value::little-float-32>> = binary_part(data, index * 4, 4)
    value
  end

  defp valid_floats?(<<>>), do: true
  defp valid_floats?(<<_value::little-float-32, rest::binary>>), do: valid_floats?(rest)
  defp valid_floats?(_data), do: false
end
