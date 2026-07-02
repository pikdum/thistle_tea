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
    objective_slots: [],
    point_map_id: 0,
    point_x: 0.0,
    point_y: 0.0,
    point_opt: 0,
    reward_items: [],
    reward_choice_items: [],
    reward_money: 0,
    reward_money_max_level: 0,
    reward_xp: 0,
    reward_spell: 0,
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
      objective_slots: objective_slots(row),
      point_map_id: row.point_map_id,
      point_x: row.point_x,
      point_y: row.point_y,
      point_opt: row.point_opt,
      reward_items: id_count_pairs(row, :rew_item_id, :rew_item_count, 4),
      reward_choice_items: id_count_pairs(row, :rew_choice_item_id, :rew_choice_item_count, 6),
      reward_money: row.rew_or_req_money,
      reward_money_max_level: row.rew_money_max_level,
      reward_xp: row.rew_xp,
      reward_spell: row.rew_spell,
      details_emotes: emote_pairs(row, :details_emote, :details_emote_delay),
      incomplete_emote: row.incomplete_emote,
      complete_emote: row.complete_emote,
      offer_reward_emotes: emote_pairs(row, :offer_reward_emote, :offer_reward_emote_delay)
    }
  end

  def deliver?(%__MODULE__{required_items: required_items}), do: required_items != []

  def auto_complete?(%__MODULE__{method: 0}), do: true
  def auto_complete?(%__MODULE__{}), do: false

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
