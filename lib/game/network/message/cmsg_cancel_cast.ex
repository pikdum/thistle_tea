defmodule ThistleTea.Game.Network.Message.CmsgCancelCast do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_CAST

  alias ThistleTea.Game.Player.Spellcasting

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_CANCEL_CAST")
    Spellcasting.cancel(state)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
