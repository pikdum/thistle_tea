defmodule ThistleTea.Game.Network.Message.SmsgSetFactionAtwar do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SET_FACTION_ATWAR

  defstruct [:index, :enabled]

  @impl ServerMessage
  def to_binary(%__MODULE__{index: index, enabled: enabled}) do
    flags = if enabled, do: 0x02, else: 0
    <<index::little-size(32), flags>>
  end
end
