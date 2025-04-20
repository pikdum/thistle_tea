defmodule ThistleTeaGame.ClientPacket.Parse do
  def parse_string(payload, pos \\ 1)
  def parse_string(payload, _pos) when byte_size(payload) == 0, do: {:ok, payload, <<>>}

  def parse_string(payload, pos) do
    case :binary.at(payload, pos - 1) do
      0 ->
        {string, rest} = Binary.split_at(payload, pos)
        {:ok, Binary.trim_trailing(string), rest}

      _ ->
        parse_string(payload, pos + 1)
    end
  end
end
