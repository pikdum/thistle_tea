defmodule ThistleTea.Game.World.Visibility.QuestGivers do
  @moduledoc """
  Projects game-object activation and creature quest status for each viewer.

  Nothing polls. The viewer re-evaluates its visible quest givers when its own
  eligibility inputs change (level, quest state, skills, reputation, auras,
  area, world, or inventory) and when a world fact it depends on is published:
  game events on the aggregate key and scripted map events or instance data on
  its world's key. Newly visible givers are answered through the client's own
  status query.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.GameObject
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Network.Message.SmsgQuestgiverStatus
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Topics

  def personalize(
        %UpdateObject{object: %{guid: guid}, game_object: %GameObject{} = object} = update,
        %Character{} = viewer
      ) do
    if quest_object?(guid) do
      %{update | game_object: %{object | dyn_flags: flags(guid, viewer, nil)}}
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

  def enter(%State{character: %Character{internal: %Internal{world: world}}} = state) do
    key = Topics.world_facts(world)
    state = leave(state)
    :ok = Topics.subscribe(Topics.game_events())
    :ok = Topics.subscribe(key)
    %{state | world_facts_key: key}
  end

  def enter(state), do: state

  def leave(%State{world_facts_key: key} = state) when is_binary(key) do
    Topics.unsubscribe(Topics.game_events())
    Topics.unsubscribe(key)
    %{state | world_facts_key: nil}
  end

  def leave(state), do: state

  def sync(%State{character: %Character{player: %Player{}} = viewer, quest_eligibility: previous} = state) do
    case eligibility(viewer) do
      ^previous -> state
      current -> %{refresh(state) | quest_eligibility: current}
    end
  end

  def sync(state), do: state

  def refresh(%State{character: %Character{} = viewer} = state) do
    visible = MapSet.to_list(state.tracked_entities)

    state = %{
      state
      | quest_object_flags: Map.take(state.quest_object_flags, visible),
        questgiver_statuses: Map.take(state.questgiver_statuses, visible)
    }

    quest_context = Quests.ctx(viewer)
    refresh_objects(state, viewer, quest_context)
    refresh_creatures(state, viewer, quest_context)
    state
  end

  def refresh(state), do: state

  defp eligibility(%Character{unit: unit, player: player, internal: internal}) do
    {unit.level, player.quest_log, player.rewarded_quests, player.skills, player.skill_bonuses, player.reputation,
     Enum.map(unit.auras || [], & &1.spell.id), internal.area, internal.world}
  end

  defp refresh_objects(state, viewer, quest_context) do
    for {guid, previous} <- state.quest_object_flags,
        current = flags(guid, viewer, quest_context),
        current != previous do
      update = %UpdateObject{
        update_type: :values,
        object: %Object{guid: guid},
        game_object: %GameObject{dyn_flags: current}
      }

      Outbound.send_packet(update, self(), source_guid: guid)
    end
  end

  defp refresh_creatures(state, viewer, quest_context) do
    for guid <- state.tracked_entities,
        creature_questgiver?(guid) or Map.has_key?(state.questgiver_statuses, guid),
        current = creature_status(guid, viewer, quest_context),
        current != Map.get(state.questgiver_statuses, guid) do
      Outbound.send_packet(%SmsgQuestgiverStatus{guid: guid, status: current}, self(), source_guid: guid)
    end
  end

  defp creature_status(guid, viewer, quest_context) do
    if creature_questgiver?(guid), do: Quests.dialog_status(guid, viewer, quest_context), else: 0
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

  defp flags(guid, %Character{} = viewer, quest_context) do
    case GameObjectTemplateLoader.cached(Guid.entry(guid)) do
      %GameObjectTemplate{type: 10, data: data} ->
        if goober_active?(viewer, Guid.entry(guid), Enum.at(data, 1, 0)), do: 1, else: 0

      _ ->
        questgiver_flags(guid, viewer, quest_context)
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

  defp questgiver_flags(guid, viewer, quest_context) do
    if Quests.quest_menu(guid, viewer, quest_context) == [], do: 0, else: 1
  end
end
