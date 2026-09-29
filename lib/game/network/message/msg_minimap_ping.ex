defmodule ThistleTea.Game.Network.Message.MsgMinimapPing do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MINIMAP_PING

  alias ThistleTea.Game.Core.Party.Group
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.System.Party.Notifier

  defstruct [:x, :y]

  @impl ClientMessage
  def handle(%__MODULE__{x: x, y: y}, %{ready: true, guid: guid} = state) do
    case PartySystem.group_of(guid) do
      %Group{} = group ->
        Notifier.broadcast(group, %Message.MsgMinimapPingResponse{guid: guid, x: x, y: y}, except: guid)

      _ ->
        :ok
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<x::little-float-size(32), y::little-float-size(32)>> = payload
    %__MODULE__{x: x, y: y}
  end
end
