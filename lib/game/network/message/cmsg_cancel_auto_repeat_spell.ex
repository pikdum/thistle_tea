defmodule ThistleTea.Game.Network.Message.CmsgCancelAutoRepeatSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_AUTO_REPEAT_SPELL

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
