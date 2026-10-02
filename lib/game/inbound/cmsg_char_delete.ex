defmodule ThistleTea.Game.Inbound.CmsgCharDelete do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_CHAR_DELETE

  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.Outbound

  require Logger

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state) do
    Logger.info("CMSG_CHAR_DELETE: #{guid}")

    result =
      case Characters.delete(state.account.id, guid) do
        :ok -> :success
        {:error, _reason} -> :failed
      end

    Outbound.send_packet(%Message.SmsgCharDelete{result: Message.SmsgCharDelete.result(result)})
    state
  end
end
