defmodule ThistleTea.Game.Inbound.CmsgCancelAutoRepeatSpell do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CANCEL_AUTO_REPEAT_SPELL

  alias ThistleTea.Game.World.Entity.Player.Spellcasting

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Spellcasting.cancel_auto_repeat(state)
end
