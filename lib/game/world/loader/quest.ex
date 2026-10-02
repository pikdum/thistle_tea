defmodule ThistleTea.Game.World.Loader.Quest do
  @moduledoc """
  ETS cache of quest templates and questgiver/quest-ender relations from
  Mangos.
  """
  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestGraph
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]
  @supported_patch 10

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    rows = Mangos.Repo.all(Mangos.QuestTemplate)
    start_scripts = load_scripts(rows, :start_script, Mangos.QuestStartScript)
    complete_scripts = load_scripts(rows, :complete_script, Mangos.QuestEndScript)
    required_conditions = rows |> Enum.map(& &1.required_condition) |> ConditionLoader.load_by_ids()
    start_items = load_start_items()
    events = load_events()

    rows
    |> Enum.map(fn row ->
      quest = row |> build() |> attach_required_condition(required_conditions)

      %{
        quest
        | event_id: Map.get(events, quest.id, 0),
          start_item_template: Map.get(start_items, quest.id),
          start_script_steps: Map.get(start_scripts, quest.start_script_id, []),
          complete_script_steps: Map.get(complete_scripts, quest.complete_script_id, [])
      }
    end)
    |> QuestGraph.compile()
    |> Enum.each(&:ets.insert(__MODULE__, {{:quest, &1.id}, &1}))

    load_creature_relations(Mangos.CreatureQuestRelation, :giver)
    load_creature_relations(Mangos.CreatureInvolvedRelation, :ender)
    load_game_object_relations(Mangos.GameObjectQuestRelation, :giver)
    load_game_object_relations(Mangos.GameObjectInvolvedRelation, :ender)

    :ok
  end

  def append_start_steps(quest_id, steps) when is_list(steps) do
    case get(quest_id) do
      %Quest{} = quest ->
        :ets.insert(__MODULE__, {{:quest, quest_id}, %{quest | start_script_steps: quest.start_script_steps ++ steps}})
        :ok

      nil ->
        :ok
    end
  end

  def attach_required_condition(%Quest{required_condition_id: 0} = quest, _conditions), do: quest

  def attach_required_condition(%Quest{required_condition_id: condition_id} = quest, conditions)
      when condition_id > 0 do
    condition = Map.get(conditions, condition_id, Condition.unresolved(condition_id))
    %{quest | required_condition: condition}
  end

  defp load_scripts(rows, field, schema) do
    rows
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&(&1 > 0))
    |> then(&Script.load_by_ids(schema, &1))
  end

  defp load_start_items do
    from(item in Mangos.ItemTemplate, where: item.start_quest > 0, order_by: [desc: item.entry])
    |> Mangos.Repo.all()
    |> Map.new(&{&1.start_quest, ItemLoader.build_template(&1)})
  end

  defp load_events do
    from(relation in Mangos.GameEventQuest,
      join: event in Mangos.GameEvent,
      on: event.entry == relation.event,
      where: relation.event > 0 and relation.patch_min <= @supported_patch,
      select: {relation.quest, relation.event}
    )
    |> Mangos.Repo.all()
    |> Map.new()
  end

  def get(quest_id) do
    case :ets.lookup(__MODULE__, {:quest, quest_id}) do
      [{_key, %Quest{} = quest}] -> quest
      _ -> nil
    end
  end

  def given_by(creature_entry), do: relation_lookup({:giver, creature_entry})

  def given_by(:unit, entry), do: given_by(entry)
  def given_by(:game_object, entry), do: relation_lookup({:giver, :game_object, entry})
  def given_by(_type, _entry), do: []

  def ended_by(creature_entry), do: relation_lookup({:ender, creature_entry})

  def ended_by(:unit, entry), do: ended_by(entry)
  def ended_by(:game_object, entry), do: relation_lookup({:ender, :game_object, entry})
  def ended_by(_type, _entry), do: []

  defp relation_lookup(key) do
    case :ets.lookup(__MODULE__, key) do
      [{_key, quest_ids}] -> quest_ids
      _ -> []
    end
  end

  defp load_creature_relations(schema, role) do
    schema
    |> Mangos.Repo.all()
    |> Enum.group_by(fn relation -> {role, relation.id} end, fn relation -> relation.quest end)
    |> Enum.each(fn {key, quest_ids} ->
      :ets.insert(__MODULE__, {key, Enum.sort(quest_ids)})
    end)
  end

  defp load_game_object_relations(schema, role) do
    schema
    |> Mangos.Repo.all()
    |> Enum.group_by(fn relation -> {role, :game_object, relation.id} end, fn relation -> relation.quest end)
    |> Enum.each(fn {key, quest_ids} ->
      :ets.insert(__MODULE__, {key, Enum.sort(quest_ids)})
    end)
  end

  def build(%Mangos.QuestTemplate{} = row) do
    %Quest{
      id: row.entry,
      start_script_id: row.start_script,
      complete_script_id: row.complete_script,
      method: row.method,
      zone_or_sort: row.zone_or_sort,
      min_level: row.min_level,
      level: row.quest_level,
      type: row.type,
      required_classes: row.required_classes,
      required_races: row.required_races,
      required_skill: row.required_skill,
      required_skill_value: row.required_skill_value,
      required_condition_id: row.required_condition,
      reputation_objective_faction: row.rep_objective_faction,
      reputation_objective_value: row.rep_objective_value,
      required_min_reputation_faction: row.required_min_rep_faction,
      required_min_reputation_value: row.required_min_rep_value,
      required_max_reputation_faction: row.required_max_rep_faction,
      required_max_reputation_value: row.required_max_rep_value,
      suggested_players: row.suggested_players,
      limit_time: row.limit_time,
      flags: row.quest_flags,
      special_flags: row.special_flags,
      prev_quest_id: row.prev_quest_id,
      next_quest_id: row.next_quest_id,
      exclusive_group: row.exclusive_group,
      breadcrumb_for_quest_id: row.breadcrumb_for_quest_id,
      next_quest_in_chain: row.next_quest_in_chain,
      src_item_id: row.src_item_id,
      src_item_count: row.src_item_count,
      title: row.title || "",
      details: row.details || "",
      objectives_text: row.objectives || "",
      offer_reward_text: row.offer_reward_text || "",
      request_items_text: row.request_items_text || "",
      end_text: row.end_text || "",
      objective_texts: Enum.map(1..4, fn i -> Map.get(row, :"objective_text#{i}") || "" end),
      required_items: indexed_id_counts(row, :req_item_id, :req_item_count, 4),
      required_kills: required_kills(row),
      required_entity_objectives: required_entity_objectives(row),
      objective_slots: objective_slots(row),
      point_map_id: row.point_map_id,
      point_x: row.point_x,
      point_y: row.point_y,
      point_opt: row.point_opt,
      reward_items: id_count_pairs(row, :rew_item_id, :rew_item_count, 4),
      reward_choice_items: id_count_pairs(row, :rew_choice_item_id, :rew_choice_item_count, 6),
      reward_reputation: reputation_rewards(row),
      reward_money: row.rew_or_req_money,
      reward_money_max_level: row.rew_money_max_level,
      reward_xp: row.rew_xp,
      source_spell: row.src_spell,
      reward_spell: row.rew_spell,
      reward_spell_cast: row.rew_spell_cast,
      reward_mail_template_id: abs(row.rew_mail_template_id),
      reward_mail_delay_secs: row.rew_mail_delay_secs,
      reward_mail_money: row.rew_mail_money,
      details_emotes: emote_pairs(row, :details_emote, :details_emote_delay),
      incomplete_emote: row.incomplete_emote,
      complete_emote: row.complete_emote,
      offer_reward_emotes: emote_pairs(row, :offer_reward_emote, :offer_reward_emote_delay)
    }
  end

  defp id_count_pairs(row, id_prefix, count_prefix, slots) do
    Enum.flat_map(1..slots, fn i ->
      id = Map.get(row, :"#{id_prefix}#{i}") || 0
      count = Map.get(row, :"#{count_prefix}#{i}") || 0
      if id > 0, do: [{id, max(count, 1)}], else: []
    end)
  end

  defp indexed_id_counts(row, id_prefix, count_prefix, slots) do
    Enum.flat_map(1..slots, fn i ->
      id = Map.get(row, :"#{id_prefix}#{i}") || 0
      count = Map.get(row, :"#{count_prefix}#{i}") || 0
      if id > 0, do: [{i - 1, id, max(count, 1)}], else: []
    end)
  end

  defp required_kills(row) do
    Enum.flat_map(1..4, fn i ->
      entry = Map.get(row, :"req_creature_or_go_id#{i}") || 0
      count = Map.get(row, :"req_creature_or_go_count#{i}") || 0
      spell = Map.get(row, :"req_spell_cast#{i}") || 0
      if entry > 0 and spell == 0, do: [{i - 1, entry, max(count, 1)}], else: []
    end)
  end

  defp required_entity_objectives(row) do
    Enum.flat_map(1..4, fn i ->
      signed_entry = Map.get(row, :"req_creature_or_go_id#{i}") || 0
      count = Map.get(row, :"req_creature_or_go_count#{i}") || 0
      spell_id = Map.get(row, :"req_spell_cast#{i}") || 0

      case signed_entry do
        entry when entry > 0 -> [{i - 1, :creature, entry, spell_id, max(count, 1)}]
        entry when entry < 0 -> [{i - 1, :game_object, abs(entry), spell_id, max(count, 1)}]
        _entry -> []
      end
    end)
  end

  defp reputation_rewards(row) do
    Enum.flat_map(1..5, fn index ->
      faction_id = Map.fetch!(row, :"rew_rep_faction#{index}")
      value = Map.fetch!(row, :"rew_rep_value#{index}")

      if faction_id > 0 and value != 0 do
        [
          %{
            faction_id: faction_id,
            value: value,
            no_spillover?: Bitwise.band(row.rew_rep_spillover_mask, Bitwise.bsl(1, index - 1)) != 0
          }
        ]
      else
        []
      end
    end)
  end

  defp objective_slots(row) do
    Enum.map(1..4, fn i ->
      %{
        creature_or_go_id: Map.get(row, :"req_creature_or_go_id#{i}") || 0,
        creature_or_go_count: Map.get(row, :"req_creature_or_go_count#{i}") || 0,
        item_id: Map.get(row, :"req_item_id#{i}") || 0,
        item_count: Map.get(row, :"req_item_count#{i}") || 0
      }
    end)
  end

  defp emote_pairs(row, emote_prefix, delay_prefix) do
    Enum.map(1..4, fn i ->
      {Map.get(row, :"#{emote_prefix}#{i}") || 0, Map.get(row, :"#{delay_prefix}#{i}") || 0}
    end)
  end
end
