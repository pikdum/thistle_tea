defmodule ThistleTea.Util do
  import Binary, only: [split_at: 2, trim_trailing: 1, reverse: 1]
  import Bitwise, only: [|||: 2, <<<: 2, &&&: 2]

  @smsg_update_object 0x0A9
  @smsg_compressed_update_object 0x1F6

  @range 250

  def random_int(min, max) do
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
        if (mask &&& 1 <<< i) != 0 do
          <<byte::8, remaining::binary>> = data
          {guid_acc ||| byte <<< (i * 8), remaining}
        else
          {guid_acc, data}
        end
      end)

    {:binary.decode_unsigned(<<guid::64>>), remaining_data}
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
