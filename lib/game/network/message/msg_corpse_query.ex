defmodule ThistleTea.Game.Network.Message.MsgCorpseQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_CORPSE_QUERY

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.World
  alias ThistleTea.Game.WorldRef

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    corpse_guid = Corpse.guid_for(guid)

    case World.position(corpse_guid) do
      {%WorldRef{map_id: map_id}, x, y, z} ->
        Network.send_packet(%Message.MsgCorpseQueryResponse{map: map_id, position: {x, y, z}})

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
