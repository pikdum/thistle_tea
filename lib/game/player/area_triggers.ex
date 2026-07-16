defmodule ThistleTea.Game.Player.AreaTriggers do
  @moduledoc """
  Validates area-trigger proximity and applies quest, rest, and cached portal
  behavior for a player.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  @trigger_range_delta 5.0

  def handle(%{ready: true, character: %Character{} = character} = state, trigger_id) when is_integer(trigger_id) do
    {x, y, z, _orientation} = character.movement_block.position

    with %{} = trigger <- AreaTriggerLoader.get(trigger_id),
         true <-
           AreaTriggerLoader.inside?(
             trigger,
             character.internal.world.map_id,
             {x, y, z},
             @trigger_range_delta
           ) do
      state
      |> maybe_explore_quest(trigger_id)
      |> enter_tavern_or_teleport(trigger_id)
    else
      _out_of_range -> state
    end
  end

  def handle(state, _trigger_id), do: state

  defp maybe_explore_quest(%{character: %Character{} = character} = state, trigger_id) do
    quest_id = AreaTriggerLoader.quest_for(trigger_id)

    if is_integer(quest_id) and Death.alive?(character) do
      Quests.explore_area(state, quest_id)
    else
      state
    end
  end

  defp enter_tavern_or_teleport(state, trigger_id) do
    if AreaTriggerLoader.tavern?(trigger_id) do
      PlayerRest.enter_tavern(state, trigger_id)
    else
      maybe_teleport(state, AreaTriggerLoader.teleport(trigger_id))
    end
  end

  defp maybe_teleport(state, nil), do: state

  defp maybe_teleport(%{character: %Character{} = character} = state, teleport) do
    cond do
      character.unit.level < teleport.required_level ->
        reject_teleport(state, teleport)

      teleport.required_condition > 0 ->
        reject_teleport(state, teleport)

      true ->
        start_teleport(state, teleport)
    end
  end

  defp reject_teleport(state, %{message: message}) when is_binary(message) and message != "" do
    Network.send_packet(%Message.SmsgAreaTriggerMessage{message: message})
    state
  end

  defp reject_teleport(state, _teleport), do: state

  defp start_teleport(state, teleport) do
    case destination_world(teleport.target_map, state.guid) do
      {:ok, world} ->
        GenServer.cast(
          self(),
          {:start_teleport, teleport.x, teleport.y, teleport.z, teleport.orientation, world}
        )

      _error ->
        :ok
    end

    state
  end

  defp destination_world(map_id, guid) do
    if AreaTriggerLoader.instance_map?(map_id) do
      InstanceSystem.enter(map_id, guid)
    else
      {:ok, WorldRef.open(map_id)}
    end
  end
end
