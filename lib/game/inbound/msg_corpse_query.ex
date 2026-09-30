defmodule ThistleTea.Game.Inbound.MsgCorpseQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_CORPSE_QUERY

  alias ThistleTea.Game.World.Entity.Player.Corpses

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Corpses.query(state)
end
