defmodule ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INVENTORY_CHANGE_FAILURE

  defstruct code: 0, required_level: 0, item1_guid: 0, item2_guid: 0

  @cant_equip_level_i 1

  @impl ServerMessage
  def to_binary(%__MODULE__{code: 0}), do: <<0>>

  def to_binary(%__MODULE__{code: code} = message) do
    <<code>> <>
      level_binary(message) <>
      <<message.item1_guid::little-size(64), message.item2_guid::little-size(64), 0>>
  end

  defp level_binary(%__MODULE__{code: @cant_equip_level_i, required_level: level}), do: <<level::little-size(32)>>
  defp level_binary(%__MODULE__{}), do: <<>>
end
