defmodule ThistleTea.Game.Entity.Data.Quest do
  @moduledoc """
  Internal quest struct translated from Mangos `quest_template` rows:
  objectives, rewards, requirements, and helpers for delivery/auto-complete
  classification.
  """
  alias ThistleTea.DB.Mangos

  defstruct [
    :id,
    method: 2,
    zone_or_sort: 0,
    min_level: 0,
    level: 0,
    type: 0,
    required_classes: 0,
    required_races: 0,
    reputation_objective_faction: 0,
    reputation_objective_value: 0,
    required_min_reputation_faction: 0,
    required_min_reputation_value: 0,
    required_max_reputation_faction: 0,
    required_max_reputation_value: 0,
    suggested_players: 0,
    limit_time: 0,
    flags: 0,
    special_flags: 0,
    prev_quest_id: 0,
    next_quest_id: 0,
    exclusive_group: 0,
    next_quest_in_chain: 0,
    src_item_id: 0,
    src_item_count: 0,
    title: "",
    details: "",
    objectives_text: "",
    offer_reward_text: "",
    request_items_text: "",
    end_text: "",
    objective_texts: [],
    required_items: [],
    required_kills: [],
    required_entity_objectives: [],
    objective_slots: [],
    point_map_id: 0,
    point_x: 0.0,
    point_y: 0.0,
    point_opt: 0,
    reward_items: [],
    reward_choice_items: [],
    reward_reputation: [],
    reward_money: 0,
    reward_money_max_level: 0,
    reward_xp: 0,
    reward_spell: 0,
    reward_mail_template_id: 0,
    reward_mail_delay_secs: 0,
    reward_mail_money: 0,
    details_emotes: [],
    incomplete_emote: 0,
    complete_emote: 0,
    offer_reward_emotes: []
  ]

  def build(%Mangos.QuestTemplate{} = row) do
    %__MODULE__{
      id: row.entry,
      method: row.method,
      zone_or_sort: row.zone_or_sort,
      min_level: row.min_level,
      level: row.quest_level,
      type: row.type,
      required_classes: row.required_classes,
      required_races: row.required_races,
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
      reward_spell: row.rew_spell,
      reward_mail_template_id: abs(row.rew_mail_template_id),
      reward_mail_delay_secs: row.rew_mail_delay_secs,
      reward_mail_money: row.rew_mail_money,
      details_emotes: emote_pairs(row, :details_emote, :details_emote_delay),
      incomplete_emote: row.incomplete_emote,
      complete_emote: row.complete_emote,
      offer_reward_emotes: emote_pairs(row, :offer_reward_emote, :offer_reward_emote_delay)
    }
  end

  def deliver?(%__MODULE__{required_items: required_items}), do: required_items != []

  def auto_complete?(%__MODULE__{method: 0}), do: true
  def auto_complete?(%__MODULE__{}), do: false

  @special_flag_exploration_or_event 0x2

  def exploration?(%__MODULE__{special_flags: special_flags}) do
    Bitwise.band(special_flags || 0, @special_flag_exploration_or_event) != 0
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
