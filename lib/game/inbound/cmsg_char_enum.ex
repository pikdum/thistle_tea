defmodule ThistleTea.Game.Inbound.CmsgCharEnum do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHAR_ENUM

  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.Outbound

  require Logger

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_CHAR_ENUM")

    state.account.id
    |> Characters.enum()
    |> Outbound.send_packet()

    state
  end
end
