defmodule ThistleTea.Game.Core.Condition do
  @moduledoc """
  One VMangos `conditions` row resolved into a semantic tree at load time, and
  the pure three-valued evaluator over those trees. Raw values and flags are
  retained so evaluation can preserve exact upstream semantics while
  capability support is migrated.

  `specialize/2` partially evaluates a tree against the facts a spawn can
  never change (its database guid and the content patch): the leaves those
  facts decide become results, the combinators fold around them, and whatever
  is left is returned as a smaller tree with the same semantics.

  Script ports may also build `:mini_pet` leaves, which have no VMangos id:
  they hold when the target's noncombat pet is the creature entry in
  `value1`, or any noncombat pet when it is 0.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Context
  alias ThistleTea.Game.Core.Condition.Leaf
  alias ThistleTea.Game.Core.Condition.Reason
  alias ThistleTea.Game.Core.Condition.Result

  defstruct entry: 0,
            type: {:unsupported, 0},
            value1: 0,
            value2: 0,
            value3: 0,
            value4: 0,
            reverse?: false,
            swap_targets?: false,
            children: []

  @flag_reverse_result 0x1
  @flag_swap_targets 0x2
  @static_types [:none, :db_guid, :content_patch]

  @types %{
    -3 => :not,
    -2 => :or,
    -1 => :and,
    0 => :none,
    1 => :aura,
    2 => :item,
    3 => :item_equipped,
    4 => :area_id,
    5 => :reputation_rank_min,
    6 => :team,
    7 => :skill,
    8 => :quest_rewarded,
    9 => :quest_taken,
    10 => :argent_dawn_commission_aura,
    11 => :saved_variable,
    12 => :active_game_event,
    13 => :cannot_path_to_victim,
    14 => :race_class,
    15 => :level,
    16 => :source_entry,
    17 => :spell,
    18 => :instance_script,
    19 => :quest_available,
    20 => :nearby_creature,
    21 => :nearby_game_object,
    22 => :quest_none,
    23 => :item_with_bank,
    24 => :content_patch,
    25 => :escort,
    26 => :active_holiday,
    27 => :gender,
    28 => :is_player,
    29 => :skill_below,
    30 => :reputation_rank_max,
    31 => :has_flag,
    32 => :last_waypoint,
    33 => :map_id,
    34 => :instance_data,
    35 => :map_event_data,
    36 => :map_event_active,
    37 => :line_of_sight,
    38 => :distance_to_target,
    39 => :moving,
    40 => :has_pet,
    41 => :health_percent,
    42 => :mana_percent,
    43 => :in_combat,
    44 => :reaction,
    45 => :in_group,
    46 => :alive,
    47 => :map_event_targets,
    48 => :object_spawned,
    49 => :object_loot_state,
    50 => :object_fit_condition,
    51 => :pvp_rank,
    52 => :db_guid,
    53 => :local_time,
    54 => :distance_to_position,
    55 => :object_go_state,
    56 => :nearby_player,
    57 => :creature_group_member,
    58 => :creature_group_dead,
    59 => :area_explored
  }

  def build(row, children) when is_map(row) and is_list(children) do
    type = type(row.type)

    %__MODULE__{
      entry: row.condition_entry,
      type: resolve_type(type, children),
      value1: int(row.value1),
      value2: int(row.value2),
      value3: int(row.value3),
      value4: int(row.value4),
      reverse?: flag?(row.flags, @flag_reverse_result),
      swap_targets?: flag?(row.flags, @flag_swap_targets),
      children: children
    }
  end

  def combinator_child_entries(row) when is_map(row) do
    case type(row.type) do
      :not -> Enum.filter([row.value1], &positive?/1)
      type when type in [:or, :and] -> Enum.filter([row.value1, row.value2, row.value3, row.value4], &positive?/1)
      type when type in [:map_event_targets, :object_fit_condition] -> Enum.filter([row.value2], &positive?/1)
      _ -> []
    end
  end

  def type(id) when is_integer(id), do: Map.get(@types, id, {:unsupported, id})

  def known_types, do: @types

  def unresolved(entry) when is_integer(entry) do
    %__MODULE__{entry: entry, type: {:unsupported, :unresolved}}
  end

  defp resolve_type(type, children) when type in [:not, :or, :and, :map_event_targets, :object_fit_condition] do
    if children == [] or Enum.any?(children, &unresolved?/1) do
      {:unsupported, :unresolved}
    else
      type
    end
  end

  defp resolve_type(type, _children), do: type

  defp positive?(value), do: is_integer(value) and value > 0

  defp int(value) when is_integer(value), do: value
  defp int(_value), do: 0

  defp flag?(flags, bit) when is_integer(flags), do: (flags &&& bit) != 0
  defp flag?(_flags, _bit), do: false

  defp unresolved?(nil), do: true
  defp unresolved?(%__MODULE__{type: {:unsupported, :unresolved}}), do: true
  defp unresolved?(%__MODULE__{}), do: false

  @target_facts %{
    aura: :auras,
    item: :item_counts,
    item_with_bank: :item_counts_with_bank,
    item_equipped: :equipped_item_ids,
    reputation_rank_min: :reputation_ranks,
    pvp_rank: :honor_rank,
    team: :team,
    skill: :skills,
    quest_rewarded: :rewarded_quests,
    quest_taken: :quest_log,
    argent_dawn_commission_aura: :argent_dawn_commission,
    race_class: :race_class,
    level: :level,
    spell: :spell_ids,
    quest_available: :quest_availability,
    quest_none: :quest_log,
    gender: :gender,
    is_player: :kind,
    skill_below: :skills,
    reputation_rank_max: :reputation_ranks,
    moving: :moving,
    has_pet: :has_pet,
    health_percent: :health,
    mana_percent: :mana,
    in_combat: :combat,
    in_group: :group,
    alive: :alive,
    object_spawned: :go_spawned,
    object_loot_state: :loot_state,
    object_go_state: :go_state,
    area_explored: :explored_areas
  }

  @type result :: :met | :unmet | {:unknown, [Reason.t()]}

  def evaluate(%Context{}, nil), do: :met

  def evaluate(%Context{} = context, %Condition{} = condition) do
    case precomputed(context, condition) do
      {:ok, result} -> result
      :missing -> evaluate_resolved(context, condition)
    end
  end

  def specialize(%Context{} = context, %Condition{type: type} = condition) when type in @static_types do
    case evaluate(context, condition) do
      result when result in [:met, :unmet] -> result
      {:unknown, _reasons} -> condition
    end
  end

  def specialize(%Context{} = context, %Condition{type: type, children: [_ | _] = children} = condition)
      when type in [:not, :or, :and] do
    inner = if condition.swap_targets?, do: Context.swap(context), else: context

    children
    |> Enum.map(&specialize(inner, &1))
    |> fold(condition)
    |> fold_reverse(condition)
  end

  def specialize(%Context{}, %Condition{} = condition), do: condition

  def compare(actual, expected, mode), do: Result.compare(actual, expected, mode)

  defp fold([result], %Condition{type: :not}) when result in [:met, :unmet], do: Result.negate(result)
  defp fold([%Condition{} = child], %Condition{type: :not} = condition), do: %{condition | children: [child]}
  defp fold(_children, %Condition{type: :not} = condition), do: condition
  defp fold(children, %Condition{type: :or} = condition), do: fold_around(children, condition, :met, :unmet)
  defp fold(children, %Condition{type: :and} = condition), do: fold_around(children, condition, :unmet, :met)

  defp fold_around(children, condition, dominant, neutral) do
    if dominant in children do
      dominant
    else
      case Enum.reject(children, &(&1 == neutral)) do
        [] -> neutral
        remaining -> %{condition | children: remaining}
      end
    end
  end

  defp fold_reverse(result, %Condition{reverse?: true}) when result in [:met, :unmet], do: Result.negate(result)
  defp fold_reverse(result, _condition), do: result

  defp precomputed(%Context{environment: %{condition_results: results}}, %Condition{} = condition)
       when is_map(results) do
    case Map.fetch(results, condition_key(condition)) do
      {:ok, result} -> {:ok, precomputed_result(result)}
      :error -> :missing
    end
  end

  defp precomputed(%Context{}, %Condition{}), do: :missing

  defp precomputed_result(result) when result in [:met, :unmet], do: result
  defp precomputed_result({:unknown, reasons}), do: {:unknown, reasons}
  defp precomputed_result(result) when is_boolean(result), do: Result.truth(result)

  defp condition_key(%Condition{entry: entry}) when is_integer(entry) and entry > 0, do: entry
  defp condition_key(%Condition{} = condition), do: condition

  defp evaluate_resolved(context, condition) do
    context = if condition.swap_targets?, do: Context.swap(context), else: context
    result = evaluate_type(context, condition)
    if condition.reverse?, do: Result.negate(result), else: result
  end

  defp evaluate_type(_context, %Condition{type: :none}), do: :met

  defp evaluate_type(context, %Condition{type: :not, children: [child]}) do
    context |> evaluate(child) |> Result.negate()
  end

  defp evaluate_type(context, %Condition{type: :or, children: [_ | _] = children}) do
    children |> Enum.map(&evaluate(context, &1)) |> Result.combine_or()
  end

  defp evaluate_type(context, %Condition{type: :and, children: [_ | _] = children}) do
    children |> Enum.map(&evaluate(context, &1)) |> Result.combine_and()
  end

  defp evaluate_type(_context, %Condition{type: type} = condition) when type in [:not, :or, :and] do
    Result.unknown(condition, :malformed_tree)
  end

  defp evaluate_type(_context, %Condition{type: {:unsupported, :unresolved}} = condition) do
    Result.unknown(condition, :unresolved_tree)
  end

  defp evaluate_type(_context, %Condition{type: {:unsupported, id}} = condition) do
    Result.unknown(condition, {:unsupported_condition_type, id})
  end

  defp evaluate_type(context, %Condition{} = condition) do
    case Leaf.evaluate(context, condition) do
      {:handled, result} -> result
      :unhandled -> Result.unknown(condition, missing_capability(condition.type))
    end
  end

  defp missing_capability(:source_entry), do: {:missing_fact, :source, :entry}
  defp missing_capability(:db_guid), do: {:missing_fact, :source, :db_guid}

  defp missing_capability(type) when is_map_key(@target_facts, type),
    do: {:missing_fact, :target, Map.fetch!(@target_facts, type)}

  defp missing_capability(type), do: {:unsupported_capability, type}
end
