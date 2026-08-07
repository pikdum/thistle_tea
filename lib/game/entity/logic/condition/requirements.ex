defmodule ThistleTea.Game.Entity.Logic.Condition.Requirements do
  @moduledoc """
  Pure tree scan describing the facts a boundary must collect before condition
  evaluation.
  """

  alias ThistleTea.Game.Entity.Data.Condition

  @scripted_event_types [
    :escort,
    :map_event_data,
    :map_event_active,
    :map_event_targets,
    :nearby_creature,
    :nearby_game_object,
    :nearby_player,
    :line_of_sight,
    :distance_to_target,
    :distance_to_position,
    :reaction,
    :object_fit_condition
  ]

  @source_fields %{
    source_entry: :entry,
    db_guid: :db_guid,
    cannot_path_to_victim: :cannot_path_to_victim,
    has_flag: :typed_flags,
    last_waypoint: :last_waypoint,
    creature_group_member: :formation,
    creature_group_dead: :formation
  }

  @target_fields %{
    aura: :auras,
    item: :item_counts,
    item_equipped: :equipped_items,
    reputation_rank_min: :reputation,
    team: :team,
    skill: :skills,
    quest_rewarded: :rewarded_quests,
    quest_taken: :quest_log,
    argent_dawn_commission_aura: :auras,
    race_class: :race_class,
    level: :level,
    spell: :spellbook,
    quest_available: :quest_log,
    quest_none: :quest_log,
    item_with_bank: :item_counts_with_bank,
    gender: :gender,
    is_player: :kind,
    skill_below: :skills,
    reputation_rank_max: :reputation,
    moving: :moving,
    has_pet: :pet,
    health_percent: :health,
    mana_percent: :mana,
    in_combat: :combat,
    in_group: :group,
    alive: :alive,
    object_spawned: :go_spawned,
    object_loot_state: :loot_state,
    pvp_rank: :honor_rank,
    object_go_state: :go_state,
    area_explored: :explored_areas
  }

  def plan(conditions) when is_list(conditions) do
    Enum.reduce(conditions, MapSet.new(), &scan(&1, :source, :target, &2))
  end

  def plan(%Condition{} = condition), do: plan([condition])
  def plan(nil), do: MapSet.new()

  def environment_conditions(conditions) when is_list(conditions) do
    conditions
    |> Enum.flat_map(&environment_condition/1)
    |> Enum.uniq_by(&condition_key/1)
  end

  def environment_conditions(%Condition{} = condition), do: environment_conditions([condition])
  def environment_conditions(nil), do: []

  defp environment_condition(nil), do: []

  defp environment_condition(%Condition{type: type} = condition) when type in @scripted_event_types, do: [condition]

  defp environment_condition(%Condition{type: type, children: children}) when type in [:not, :or, :and],
    do: Enum.flat_map(children, &environment_condition/1)

  defp environment_condition(%Condition{}), do: []

  defp scan(nil, _source, _target, requirements), do: requirements

  defp scan(%Condition{} = condition, source, target, requirements) do
    {source, target} = if condition.swap_targets?, do: {target, source}, else: {source, target}
    scan_condition(condition, source, target, requirements)
  end

  defp scan_condition(%Condition{type: :none}, _source, _target, requirements), do: requirements

  defp scan_condition(%Condition{type: type, children: children}, source, target, requirements)
       when type in [:not, :or, :and] do
    Enum.reduce(children, requirements, &scan(&1, source, target, &2))
  end

  defp scan_condition(%Condition{type: :map_event_targets} = condition, source, _target, requirements) do
    requirements = MapSet.put(requirements, {:scripted_event_targets, condition.value1})
    target = {:scripted_event_target, condition.value1}
    Enum.reduce(condition.children, requirements, &scan(&1, source, target, &2))
  end

  defp scan_condition(%Condition{type: :object_fit_condition} = condition, source, _target, requirements) do
    requirements = MapSet.put(requirements, {:game_object_spawn, condition.value1})
    target = {:game_object_spawn, condition.value1}
    Enum.reduce(condition.children, requirements, &scan(&1, source, target, &2))
  end

  defp scan_condition(%Condition{type: :aura} = condition, _source, target, requirements) do
    MapSet.put(requirements, {:aura, target, condition.value1, condition.value2})
  end

  defp scan_condition(%Condition{type: :item} = condition, _source, target, requirements) do
    MapSet.put(requirements, {:item_count, target, condition.value1})
  end

  defp scan_condition(%Condition{type: :item_with_bank} = condition, _source, target, requirements) do
    MapSet.put(requirements, {:bank_item_count, target, condition.value1})
  end

  defp scan_condition(%Condition{type: :item_equipped} = condition, _source, target, requirements) do
    MapSet.put(requirements, {:item_equipped, target, condition.value1})
  end

  defp scan_condition(%Condition{type: type} = condition, _source, target, requirements)
       when type in [:quest_rewarded, :quest_taken, :quest_available, :quest_none] do
    requirements
    |> MapSet.put({:subject, target, Map.fetch!(@target_fields, type)})
    |> maybe_put_quest(type, condition.value1)
  end

  defp scan_condition(%Condition{type: :area_explored} = condition, _source, target, requirements) do
    MapSet.put(requirements, {:area_explored, target, condition.value1})
  end

  defp scan_condition(%Condition{type: type} = condition, source, target, requirements) do
    MapSet.put(requirements, requirement(type, condition, source, target))
  end

  defp requirement(type, _condition, source, _target) when is_map_key(@source_fields, type),
    do: {:subject, source, Map.fetch!(@source_fields, type)}

  defp requirement(type, _condition, _source, target) when is_map_key(@target_fields, type),
    do: {:subject, target, Map.fetch!(@target_fields, type)}

  defp requirement(:area_id, _condition, source, target), do: {:subject, {:first_available, source, target}, :area_id}
  defp requirement(:saved_variable, condition, _source, _target), do: {:saved_variable, condition.value1}
  defp requirement(:active_game_event, condition, _source, _target), do: {:active_game_event, condition.value1}

  defp requirement(:instance_script, condition, source, target),
    do: {:instance_script, condition.value1, condition.value2, source, target}

  defp requirement(:nearby_creature, condition, _source, target) do
    {:nearby_creature, target, condition.value1, condition.value2, condition.value3 != 0, condition.value4 != 0}
  end

  defp requirement(:nearby_game_object, condition, _source, target),
    do: {:nearby_game_object, target, condition.value1, condition.value2}

  defp requirement(:content_patch, _condition, _source, _target), do: :content_patch

  defp requirement(:escort, condition, source, target),
    do: {:escort, source, target, condition.value1, condition.value2}

  defp requirement(:active_holiday, condition, _source, _target), do: {:active_holiday, condition.value1}
  defp requirement(:map_id, _condition, _source, _target), do: :map_id
  defp requirement(:instance_data, condition, _source, _target), do: {:instance_data, condition.value1}

  defp requirement(:map_event_data, condition, _source, _target),
    do: {:scripted_event_data, condition.value1, condition.value2}

  defp requirement(:map_event_active, condition, _source, _target), do: {:scripted_event_active, condition.value1}
  defp requirement(:line_of_sight, _condition, source, target), do: {:line_of_sight, source, target}
  defp requirement(:distance_to_target, _condition, source, target), do: {:distance, source, target}
  defp requirement(:reaction, _condition, source, target), do: {:reaction, target, source}
  defp requirement(:local_time, _condition, _source, _target), do: :current_time

  defp requirement(:distance_to_position, condition, _source, target),
    do: {:distance_to_position, target, {condition.value1, condition.value2, condition.value3}}

  defp requirement(:nearby_player, condition, _source, target),
    do: {:nearby_player, target, condition.value1, condition.value2}

  defp requirement({:unsupported, type}, _condition, _source, _target), do: {:unsupported, type}
  defp requirement(type, _condition, _source, _target), do: {:capability, type}

  defp maybe_put_quest(requirements, :quest_available, quest_id), do: MapSet.put(requirements, {:quest, quest_id})
  defp maybe_put_quest(requirements, _type, _quest_id), do: requirements

  defp condition_key(%Condition{entry: entry}) when is_integer(entry) and entry > 0, do: {:entry, entry}
  defp condition_key(%Condition{} = condition), do: {:condition, condition}
end
