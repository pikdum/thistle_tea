defmodule ThistleTea.Util do
  import Binary, only: [split_at: 2, trim_trailing: 1, reverse: 1]
  import Bitwise, only: [|||: 2, <<<: 2]

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
