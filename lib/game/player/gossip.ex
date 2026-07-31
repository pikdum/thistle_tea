defmodule ThistleTea.Game.Player.Gossip do
  @moduledoc """
  Player boundary for gossip actions that execute resolved VMangos scripts.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgGossipHello
  alias ThistleTea.Game.Network.Message.CmsgTrainerList
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader

  def select(%{character: %Character{} = character} = state, guid, gossip_list_id) do
    option_ids = %{
      vendor: GossipLoader.option_vendor(),
      taxi: GossipLoader.option_taxi(),
      trainer: GossipLoader.option_trainer(),
      spirit_healer: GossipLoader.option_spirit_healer()
    }

    option =
      state
      |> Map.get(:gossip_menu_options, [])
      |> Enum.find(fn %Option{id: id} -> id == gossip_list_id end)

    dispatch(state, character, guid, option, option_ids)
  end

  def select(state, _guid, _gossip_list_id), do: state

  defp dispatch(state, _character, _guid, nil, _option_ids), do: state

  defp dispatch(state, _character, _guid, %Option{taxi_path_steps: [_ | _] = steps}, _option_ids) do
    run_taxi_script(state, steps)
  end

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{vendor: option_id}) do
    Network.send_packet(%Message.SmsgListInventory{
      vendor_guid: guid,
      items: VendorLoader.items(Guid.entry(guid))
    })

    state
  end

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{taxi: option_id}) do
    Taxi.query(state, guid)
  end

  defp dispatch(state, _character, guid, %Option{option_id: option_id}, %{trainer: option_id}) do
    CmsgTrainerList.send_list(state, guid)
  end

  defp dispatch(state, character, guid, %Option{option_id: option_id}, %{spirit_healer: option_id}) do
    if not Death.alive?(character) do
      Network.send_packet(%Message.SmsgSpiritHealerConfirm{guid: guid})
    end

    state
  end

  defp dispatch(state, character, guid, %Option{action_menu_id: action_menu_id}, _option_ids) do
    case GossipLoader.get_menu(action_menu_id) do
      %Menu{} = menu ->
        CmsgGossipHello.send_menu(guid, menu, CmsgGossipHello.quest_items(guid, character), state)

      nil ->
        state
    end
  end

  def run_taxi_script(%{character: %Character{} = character} = state, steps) when is_list(steps) do
    Network.send_packet(%Message.SmsgGossipComplete{})
    {character, _blackboard} = Script.run(character, Blackboard.new(), steps, character.object.guid, Time.now())
    character = EventSink.emit_pending(character)
    %{state | character: character, gossip_menu_options: []}
  end
end
