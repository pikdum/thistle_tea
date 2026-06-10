defmodule ThistleTea.Game.Network.Message.MsgCorpseQuery do
  use ThistleTea.Game.Network.ClientMessage, :MSG_CORPSE_QUERY

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.World.SpatialHash

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    corpse_guid = Corpse.guid_for(guid)

    case SpatialHash.get_entity(corpse_guid) do
      {^corpse_guid, map, x, y, z} ->
        Network.send_packet(%Message.MsgCorpseQueryResponse{map: map, position: {x, y, z}})

      _ ->
        Network.send_packet(%Message.MsgCorpseQueryResponse{})
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
