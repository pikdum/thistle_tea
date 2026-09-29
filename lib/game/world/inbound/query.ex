defmodule ThistleTea.Game.World.Inbound.Query do
  @moduledoc "Handles decoded cache query client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Login
  alias ThistleTea.Game.World.Entity.Player.Pets
  alias ThistleTea.Game.World.Entity.Player.Queries
  alias ThistleTea.Game.World.Outbound

  def messages do
    [
      Message.CmsgCreatureQuery,
      Message.CmsgGameobjectQuery,
      Message.CmsgItemNameQuery,
      Message.CmsgItemQuerySingle,
      Message.CmsgNameQuery,
      Message.CmsgNpcTextQuery,
      Message.CmsgPageTextQuery,
      Message.CmsgPetNameQuery,
      Message.CmsgQueryTime,
      Message.CmsgQuestQuery
    ]
  end

  def handle(%Message.CmsgCreatureQuery{entry: entry, guid: guid}, state),
    do: entry |> Queries.creature(guid) |> reply(state)

  def handle(%Message.CmsgGameobjectQuery{entry: entry, guid: guid}, state),
    do: entry |> Queries.game_object(guid) |> reply(state)

  def handle(%Message.CmsgItemNameQuery{item_id: item_id}, state), do: item_id |> Queries.item_name() |> reply(state)
  def handle(%Message.CmsgItemQuerySingle{item_id: item_id}, state), do: item_id |> Queries.item() |> reply(state)
  def handle(%Message.CmsgNameQuery{guid: guid}, state), do: guid |> Queries.name() |> reply(state)
  def handle(%Message.CmsgNpcTextQuery{text_id: text_id}, state), do: text_id |> Queries.npc_text() |> reply(state)
  def handle(%Message.CmsgPageTextQuery{page_id: page_id}, state), do: page_id |> Queries.pages() |> reply(state)
  def handle(%Message.CmsgPetNameQuery{pet_number: number, pet_guid: guid}, state), do: Pets.query(state, guid, number)
  def handle(%Message.CmsgQueryTime{}, state), do: Login.query_time(state)
  def handle(%Message.CmsgQuestQuery{quest_id: quest_id}, state), do: quest_id |> Queries.quest() |> reply(state)

  defp reply(nil, state), do: state

  defp reply(response, state) do
    Outbound.send_packet(response)
    state
  end
end
