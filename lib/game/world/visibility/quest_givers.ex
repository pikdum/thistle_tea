defmodule ThistleTea.Game.World.Visibility.QuestGivers do
  @moduledoc """
  Projects game-object activation and creature quest status for each viewer,
  refreshing changed eligibility through the visibility tick.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestRequirements
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgQuestgiverStatus
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata

  def personalize(
        %UpdateObject{object: %{guid: guid}, game_object: %GameObject{} = object} = update,
        %Character{} = viewer
      ) do
    if quest_object?(guid) do
      %{update | game_object: %{object | dyn_flags: flags(guid, viewer)}}
    else
      update
    end
  end

  def personalize(update, _viewer), do: update

  def remember(%State{} = state, %UpdateObject{object: %{guid: guid}, game_object: %GameObject{dyn_flags: flags}})
      when is_integer(flags) do
    if quest_object?(guid) do
      %{state | quest_object_flags: Map.put(state.quest_object_flags, guid, flags)}
    else
      state
    end
  end

  def remember(%State{} = state, %SmsgQuestgiverStatus{guid: guid, status: status}) do
    if Guid.type_id(guid) == :unit and MapSet.member?(state.tracked_entities, guid) do
      %{state | questgiver_statuses: Map.put(state.questgiver_statuses, guid, status)}
    else
      state
    end
  end

  def remember(state, _update), do: state

  def forget(%State{} = state, guid) do
    %{
      state
      | quest_object_flags: Map.delete(state.quest_object_flags, guid),
        questgiver_statuses: Map.delete(state.questgiver_statuses, guid)
    }
  end

  def forget(state, _guid), do: state

  def refresh(%State{character: %Character{} = viewer} = state) do
    visible = MapSet.to_list(state.tracked_entities)

    state = %{
      state
      | quest_object_flags: Map.take(state.quest_object_flags, visible),
        questgiver_statuses: Map.take(state.questgiver_statuses, visible)
    }

    refresh_objects(state, viewer)
    refresh_creatures(state, viewer)
    state
  end

  def refresh(state), do: state

  defp refresh_objects(state, viewer) do
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
  end

  defp refresh_creatures(state, viewer) do
    for guid <- state.tracked_entities,
        creature_questgiver?(guid) or Map.has_key?(state.questgiver_statuses, guid),
        current = creature_status(guid, viewer),
        current != Map.get(state.questgiver_statuses, guid) do
      Network.send_packet(%SmsgQuestgiverStatus{guid: guid, status: current}, self(), source_guid: guid)
    end
  end

  defp creature_status(guid, viewer) do
    if creature_questgiver?(guid), do: Quests.dialog_status(guid, viewer), else: 0
  end

  defp creature_questgiver?(guid) do
    case Metadata.query(guid, [:npc_flags]) do
      %{npc_flags: flags} when is_integer(flags) -> Guid.type_id(guid) == :unit and (flags &&& 0x2) != 0
      _ -> false
    end
  end

  defp quest_object?(guid) do
    case Metadata.query(guid, [:go_type]) do
      %{go_type: type} -> type in [2, 10]
      _ -> false
    end
  end

  defp flags(guid, %Character{} = viewer) do
    case TemplateLoader.cached(Guid.entry(guid)) do
      %GameObjectTemplate{type: 10, data: data} ->
        if goober_active?(viewer, Guid.entry(guid), Enum.at(data, 1, 0)), do: 1, else: 0

      _ ->
        questgiver_flags(guid, viewer)
    end
  end

  defp goober_active?(viewer, object_entry, quest_id) do
    quest_id == -1 or match?(%QuestLog.Entry{status: :incomplete}, QuestLog.get(viewer.player.quest_log, quest_id)) or
      Enum.any?(viewer.player.quest_log, fn
        {_slot, %QuestLog.Entry{status: :incomplete, quest_id: id}} ->
          case QuestLoader.get(id) do
            %Quest{} = quest ->
              match?(
                {:ok, _, _},
                QuestLog.increment_interaction(viewer.player.quest_log, quest, :game_object, object_entry)
              )

            _ ->
              false
          end

        _ ->
          false
      end)
  end

  defp questgiver_flags(guid, viewer) do
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
