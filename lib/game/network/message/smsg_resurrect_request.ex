defmodule ThistleTea.Game.Network.Message.SmsgResurrectRequest do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_RESURRECT_REQUEST

  defstruct [:guid, name: "", sickness?: false, override_timer?: true]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, name: name} = msg) when is_integer(guid) and is_binary(name) do
    <<guid::little-size(64), byte_size(name) + 1::little-size(32)>> <>
      name <>
      <<0, bool_byte(msg.sickness?), bool_byte(msg.override_timer?)>>
  end

  defp bool_byte(true), do: 1
  defp bool_byte(_value), do: 0
end
