defmodule ThistleTea.Game.Inbound.CmsgCancelCast do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CANCEL_CAST

  alias ThistleTea.Game.World.Entity.Player.Spellcasting

  require Logger

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_CANCEL_CAST")
    Spellcasting.cancel_cast_request(state)
  end
end
