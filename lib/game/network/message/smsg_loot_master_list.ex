defmodule ThistleTea.Game.Network.Message.SmsgLootMasterList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_MASTER_LIST

  defstruct looters: []

  @impl ServerMessage
  def to_binary(%__MODULE__{looters: looters}) do
    <<length(looters)::little-size(8)>> <>
      Enum.map_join(looters, fn guid -> <<guid::little-size(64)>> end)
  end
end
