defmodule ThistleTea.Game.Entity.Data.Condition do
  @moduledoc """
  One VMangos `conditions` row resolved into a semantic tree at load time.
  Raw values and flags are retained so the pure evaluator can preserve exact
  upstream semantics while capability support is migrated.
  """
  import Bitwise, only: [&&&: 2]

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
end
