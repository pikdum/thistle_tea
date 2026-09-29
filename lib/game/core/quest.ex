defmodule ThistleTea.Game.Core.Quest do
  @moduledoc """
  Internal quest struct translated from Mangos `quest_template` rows:
  objectives, rewards, requirements, and helpers for delivery/auto-complete
  classification.
  """

  defstruct [
    :id,
    event_id: 0,
    start_script_id: 0,
    complete_script_id: 0,
    start_script_steps: [],
    complete_script_steps: [],
    method: 2,
    zone_or_sort: 0,
    min_level: 0,
    level: 0,
    type: 0,
    required_classes: 0,
    required_races: 0,
    required_skill: 0,
    required_skill_value: 0,
    required_condition_id: 0,
    required_condition: nil,
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
    breadcrumb_for_quest_id: 0,
    dependencies: nil,
    next_quest_in_chain: 0,
    src_item_id: 0,
    src_item_count: 0,
    start_item_template: nil,
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
    reward_spell_cast: 0,
    reward_mail_template_id: 0,
    reward_mail_delay_secs: 0,
    reward_mail_money: 0,
    details_emotes: [],
    incomplete_emote: 0,
    complete_emote: 0,
    offer_reward_emotes: []
  ]

  def allowed_in_raid?(%__MODULE__{type: 62}), do: true
  def allowed_in_raid?(%__MODULE__{flags: flags}), do: Bitwise.band(flags || 0, 0x40) != 0

  def shareable?(%__MODULE__{flags: flags}), do: Bitwise.band(flags || 0, 0x8) != 0
  def party_accept?(%__MODULE__{flags: flags}), do: Bitwise.band(flags || 0, 0x2) != 0

  def repeatable?(%__MODULE__{special_flags: flags}), do: Bitwise.band(flags || 0, 0x1) != 0

  def event_active?(%__MODULE__{event_id: 0}, _events), do: true
  def event_active?(%__MODULE__{event_id: id}, %MapSet{} = events), do: MapSet.member?(events, id)
  def event_active?(%__MODULE__{}, _events), do: false

  def auto_rewarded?(%__MODULE__{flags: flags}), do: Bitwise.band(flags || 0, 0x400) != 0

  def reward_spell_id(%__MODULE__{reward_spell_cast: id}) when id > 0, do: id
  def reward_spell_id(%__MODULE__{reward_spell: id}), do: id

  def deliver?(%__MODULE__{required_items: required_items}), do: required_items != []

  def auto_complete?(%__MODULE__{method: 0}), do: true
  def auto_complete?(%__MODULE__{}), do: false

  @special_flag_exploration_or_event 0x2

  def exploration?(%__MODULE__{special_flags: special_flags}) do
    Bitwise.band(special_flags || 0, @special_flag_exploration_or_event) != 0
  end
end
