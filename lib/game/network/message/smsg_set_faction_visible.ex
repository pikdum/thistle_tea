defmodule ThistleTea.Game.Network.Message.SmsgSetFactionVisible do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SET_FACTION_VISIBLE

  defstruct [:index]

  @impl ServerMessage
  def to_binary(%__MODULE__{index: index}) do
    <<index::little-size(32)>>
  end
end
