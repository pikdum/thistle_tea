defmodule ThistleTea.Game.World.Visibility.QuestGivers do
  @moduledoc """
  Projects game-object quest activation for each viewer and refreshes changed
  eligibility for already visible objects through the visibility tick.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestRequirements
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Metadata

  def personalize(
        %UpdateObject{object: %{guid: guid}, game_object: %GameObject{} = object} = update,
        %Character{} = viewer
      ) do
    if questgiver?(guid) do
      %{update | game_object: %{object | dyn_flags: flags(guid, viewer)}}
    else
      update
    end
  end

  def personalize(update, _viewer), do: update

  def remember(%State{} = state, %UpdateObject{object: %{guid: guid}, game_object: %GameObject{dyn_flags: flags}})
      when is_integer(flags) do
    if questgiver?(guid) do
      %{state | quest_object_flags: Map.put(state.quest_object_flags, guid, flags)}
    else
      state
    end
  end

  def remember(state, _update), do: state

  def forget(%State{} = state, guid) do
    %{state | quest_object_flags: Map.delete(state.quest_object_flags, guid)}
  end

  def forget(state, _guid), do: state

  def refresh(%State{character: %Character{} = viewer} = state) do
    state = %{state | quest_object_flags: Map.take(state.quest_object_flags, MapSet.to_list(state.tracked_entities))}

    for {guid, previous} <- state.quest_object_flags,
        current = flags(guid, viewer),
        current != previous do
      update = %UpdateObject{
        update_type: :values,
        object: %Object{guid: guid},
        game_object: %GameObject{dyn_flags: current}
      }

      Network.send_packet(update, self(), source_guid: guid)
    end

    state
  end

  def refresh(state), do: state

  defp questgiver?(guid), do: match?(%{go_type: 2}, Metadata.query(guid, [:go_type]))

  defp flags(guid, %Character{} = viewer) do
    {givers, enders} = Quests.npc_quests(guid)
    availability = Quests.availability(viewer, givers)

    available? =
      Enum.any?(givers, fn quest ->
        QuestRequirements.can_take?(
          quest,
          availability.quest_context,
          Map.get(availability.condition_results, quest.id)
        )
      end)

    active? =
      Enum.any?(enders, fn quest ->
        case QuestLog.get(viewer.player.quest_log, quest.id) do
          %{status: status} when status in [:incomplete, :complete] -> true
          _ -> false
        end
      end)

    if available? or active?, do: 1, else: 0
  end
end
