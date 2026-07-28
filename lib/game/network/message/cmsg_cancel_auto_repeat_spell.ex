defmodule ThistleTea.Game.Network.Message.CmsgCancelAutoRepeatSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_AUTO_REPEAT_SPELL

  alias ThistleTea.Game.Player.Spellcasting

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Spellcasting.cancel_auto_repeat(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
