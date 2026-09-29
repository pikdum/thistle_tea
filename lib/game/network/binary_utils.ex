defmodule ThistleTea.Game.Network.BinaryUtils do
  @moduledoc """
  Collection of binary related utility functions for network serialization.
  """
  import Binary, only: [split_at: 2, trim_trailing: 1]

  alias ThistleTea.Game.Core.Guid

  defdelegate pack_guid(guid), to: Guid, as: :pack
  defdelegate unpack_guid(packed), to: Guid, as: :unpack

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
