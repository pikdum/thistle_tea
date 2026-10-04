defmodule ThistleTea.Game.World.Entity.Player.AreaTriggers do
  @moduledoc """
  Validates area-trigger proximity and applies quest, script, rest, and
  cached portal behavior for a player. A battleground's entrance offers its
  list instead of a teleport. A living player who enters a scripted
  trigger runs its script on themselves, unless the trigger is still resting
  from its cooldown in their world.
  """

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.AreaTriggerCooldown
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Battlegrounds
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Entity.Player.Corpses
  alias ThistleTea.Game.World.Entity.Player.Instances
  alias ThistleTea.Game.World.Entity.Player.OutdoorPvp
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  @trigger_range_delta 5.0

  def handle(%{ready: true, guid: guid, character: %Character{} = character} = state, trigger_id)
      when is_integer(trigger_id) do
    {x, y, z, _orientation} = character.movement_block.position

    with %{} = trigger <- AreaTriggerLoader.get(trigger_id),
         true <-
           AreaTriggerLoader.inside?(
             trigger,
             character.internal.world.map_id,
             {x, y, z},
             @trigger_range_delta
           ) do
      case BattlegroundSystem.area_trigger(
             character.internal.world,
             guid,
             trigger_id,
             character.movement_block.position
           ) do
        :handled ->
          state

        :unhandled ->
          state
          |> OutdoorPvp.area_trigger(trigger_id)
          |> maybe_explore_quest(trigger_id)
          |> maybe_run_script(trigger)
          |> enter_tavern_or_teleport(trigger_id)
      end
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

  defp maybe_run_script(%{guid: guid, character: %Character{} = character} = state, trigger) do
    with true <- Death.alive?(character),
         [_ | _] = steps <- AreaTriggerLoader.script(trigger),
         true <- AreaTriggerCooldown.claim(character.internal.world, trigger, Time.now()) do
      Entity.start_script(guid, steps, guid)
    end

    state
  end

  defp enter_tavern_or_teleport(state, trigger_id) do
    cond do
      AreaTriggerLoader.tavern?(trigger_id) -> PlayerRest.enter_tavern(state, trigger_id)
      entrance = BattlegroundLoader.entrance(trigger_id) -> Battlegrounds.enter_portal(state, entrance)
      true -> maybe_teleport(state, AreaTriggerLoader.teleport(trigger_id))
    end
  end

  defp maybe_teleport(state, nil), do: state

  defp maybe_teleport(%{character: %Character{} = character} = state, teleport) do
    case Corpses.portal_destination(state, teleport) do
      {:ok, destination} -> validate_teleport(state, character, destination)
      {:error, message} -> reject_teleport(state, %{message: message})
    end
  end

  defp validate_teleport(state, character, teleport) do
    level_met? = character.unit.level >= teleport.required_level
    condition_met? = teleport_condition_met?(character, teleport.condition)

    if level_met? and condition_met?,
      do: start_teleport(state, teleport),
      else: reject_teleport(state, teleport)
  end

  defp teleport_condition_met?(_character, nil), do: true

  defp teleport_condition_met?(character, condition) do
    context = ConditionContext.build(character, [condition])
    Condition.evaluate(context, condition) == :met
  end

  defp reject_teleport(state, %{message: message}) when is_binary(message) and message != "" do
    Outbound.send_packet(%Message.SmsgAreaTriggerMessage{message: message})
    state
  end

  defp reject_teleport(state, _teleport), do: state

  defp start_teleport(state, teleport) do
    state = Corpses.revive_for_map(state, teleport.target_map)

    case destination_world(teleport.target_map, state.guid) do
      {:ok, world} ->
        GenServer.cast(
          self(),
          {:start_teleport, teleport.x, teleport.y, teleport.z, teleport.orientation, world}
        )

      {:error, reason} ->
        Instances.reject(reason)
    end

    state
  end

  defp destination_world(map_id, guid) do
    InstanceSystem.destination(map_id, guid)
  end
end
