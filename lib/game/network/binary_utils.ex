defmodule ThistleTea.Game.Network.BinaryUtils do
  @moduledoc """
  Collection of binary related utility functions for network serialization.
  """
  import Binary, only: [split_at: 2, trim_trailing: 1, reverse: 1]
  import Bitwise

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
