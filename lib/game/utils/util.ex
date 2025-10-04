defmodule ThistleTea.Util do
  import Binary, only: [split_at: 2, trim_trailing: 1, reverse: 1]
  import Bitwise, only: [|||: 2, <<<: 2, &&&: 2]

  @smsg_update_object 0x0A9
  @smsg_compressed_update_object 0x1F6

  @range 250

  def random_int(min, max) when is_float(min) and is_float(max) do
    random_int(round(min), round(max))
  end

  def random_int(min, max) when is_integer(min) and is_integer(max) do
    :rand.uniform(max - min + 1) + min - 1
  end

  def within_range(a, b) do
    within_range(a, b, @range)
  end

  def within_range(a, b, range) do
    {x1, y1, z1} = a
    {x2, y2, z2} = b

    abs(x1 - x2) <= range && abs(y1 - y2) <= range && abs(z1 - z2) <= range
  end

  def send_packet(opcode, payload) do
    GenServer.cast(self(), {:send_packet, opcode, payload})
  end

  def send_update_packet(packet) do
    compressed_packet = :zlib.compress(packet)
    original_size = byte_size(packet)
    compressed_size = byte_size(compressed_packet)

    if compressed_size >= original_size do
      send_packet(@smsg_update_object, packet)
    else
      send_packet(
        @smsg_compressed_update_object,
        <<original_size::little-size(32)>> <> compressed_packet
      )
    end
  end

  def pack_guid(guid) when is_integer(guid) do
    pack_guid(<<guid::size(64)>>)
  end

  def pack_guid(guid) when is_binary(guid) do
    {mask, data} =
      guid
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({0, []}, fn {byte, index}, {mask, data} ->
        if byte == 0 do
          {mask, data}
        else
          {mask ||| 1 <<< (byte_size(guid) - 1 - index), data ++ [byte]}
        end
      end)

    mask_size = byte_size(guid)

    <<mask::size(mask_size)>> <> reverse(:erlang.list_to_binary(data))
  end

  def unpack_guid(<<mask::8, rest::binary>>) do
    {guid, remaining_data} =
      0..7
      |> Enum.reduce({0, rest}, fn i, {guid_acc, data} ->
        if (mask &&& 1 <<< i) == 0 do
          {guid_acc, data}
        else
          <<byte::8, remaining::binary>> = data
          {guid_acc ||| byte <<< (i * 8), remaining}
        end
      end)

    {:binary.decode_unsigned(<<guid::64>>), remaining_data}
  end

  def pack_vector({x, y, z}) do
    x_packed = Bitwise.band(trunc(x / 0.25), 0x7FF)
    y_packed = Bitwise.band(trunc(y / 0.25), 0x7FF)
    z_packed = Bitwise.band(trunc(z / 0.25), 0x3FF)

    x_packed
    |> Bitwise.bor(Bitwise.bsl(y_packed, 11))
    |> Bitwise.bor(Bitwise.bsl(z_packed, 22))
  end

  def unpack_vector(packed) do
    x = Bitwise.band(packed, 0x7FF) / 4
    y = Bitwise.band(Bitwise.bsr(packed, 11), 0x7FF) / 4
    z = Bitwise.band(Bitwise.bsr(packed, 22), 0x3FF) / 4

    {x, y, z}
  end

  def calculate_movement_duration({x0, y0, z0}, {x1, y1, z1}, speed) when is_float(speed) and speed > 0 do
    distance = :math.sqrt(:math.pow(x1 - x0, 2) + :math.pow(y1 - y0, 2) + :math.pow(z1 - z0, 2))
    duration = distance / speed
    duration
  end

  def calculate_total_duration(path_list, speed) when is_list(path_list) and length(path_list) > 1 do
    path_list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [start, finish] -> calculate_movement_duration(start, finish, speed) end)
    |> Enum.sum()
  end

  def parse_string(payload, pos \\ 1)
  def parse_string(payload, _pos) when byte_size(payload) == 0, do: {:ok, payload, <<>>}

  def parse_string(payload, pos) do
    case :binary.at(payload, pos - 1) do
      0 ->
        {string, rest} = split_at(payload, pos)
        {:ok, trim_trailing(string), rest}

      _ ->
        parse_string(payload, pos + 1)
    end
  end
end
