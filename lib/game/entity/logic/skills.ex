defmodule ThistleTea.Game.Entity.Logic.Skills do
  @moduledoc """
  Player skill lines as data: a map of skill id to value, maximum, range,
  always-max flag, trained tier step, and stable PLAYER_SKILL_INFO slot.
  Ranges follow vmangos: `:level` skills cap at 5 x level and gain points
  from combat use, `:tier` skills use their trained profession cap, `:mono`
  skills stay 1/1, and `:language` skills stay 300/300.
  """
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Inventory

  @max_skill_entries 128

  @defense_skill 95
  @unarmed_skill 162
  @fishing_skill 356
  @primary_professions [164, 165, 171, 182, 186, 197, 202, 333, 393]

  def primary_profession?(skill_id), do: skill_id in @primary_professions

  def free_profession_slots(skills) when is_map(skills) do
    max(2 - Enum.count(@primary_professions, &known?(skills, &1)), 0)
  end

  def free_profession_slots(_skills), do: 2

  @weapon_subclass_skills %{
    0 => 44,
    1 => 172,
    2 => 45,
    3 => 46,
    4 => 54,
    5 => 160,
    6 => 229,
    7 => 43,
    8 => 55,
    10 => 136,
    13 => 473,
    15 => 173,
    16 => 176,
    17 => 253,
    18 => 226,
    19 => 228,
    20 => 356
  }

  def defense_skill, do: @defense_skill

  def defense_value(%{player: %{skills: skills}, unit: %{level: level}} = entity) do
    base = value(skills, @defense_skill, max_for_level(level || 1))
    {temporary, permanent} = Map.get(bonuses(entity), @defense_skill, {0, 0})
    max(base + temporary + permanent, 0)
  end

  def defense_value(%{unit: %{level: level}}), do: max_for_level(level || 1)
  def unarmed_skill, do: @unarmed_skill
  def fishing_skill, do: @fishing_skill

  def bonuses(entity) do
    for type <- [:mod_skill, :mod_skill_talent],
        aura <- Aura.auras_of_type(entity, type),
        is_integer(aura.misc_value) and is_integer(aura.amount),
        reduce: %{} do
      acc -> add_skill_bonus(acc, aura)
    end
  end

  defp add_skill_bonus(acc, aura) do
    {temporary, permanent} = Map.get(acc, aura.misc_value, {0, 0})

    bonus =
      if aura.type == :mod_skill, do: {temporary + aura.amount, permanent}, else: {temporary, permanent + aura.amount}

    Map.put(acc, aura.misc_value, bonus)
  end

  def weapon_skill_for_subclass(subclass), do: Map.get(@weapon_subclass_skills, subclass)

  def main_hand_weapon_skill(player, get_template) when is_function(get_template, 1) do
    equipped_weapon_skill(Inventory.equipment_entry(player, :mainhand), get_template, @unarmed_skill)
  end

  def off_hand_weapon_skill(player, get_template) when is_function(get_template, 1) do
    equipped_weapon_skill(Inventory.equipment_entry(player, :offhand), get_template, @unarmed_skill)
  end

  def ranged_weapon_skill(player, get_template) when is_function(get_template, 1) do
    equipped_weapon_skill(Inventory.equipment_entry(player, :ranged), get_template, nil)
  end

  defp equipped_weapon_skill(entry, get_template, fallback) do
    with entry when is_integer(entry) and entry > 0 <- entry,
         %{class: 2, subclass: subclass} <- get_template.(Item.visible_entry(entry)),
         skill when is_integer(skill) <- weapon_skill_for_subclass(subclass) do
      skill
    else
      _missing -> fallback
    end
  end

  def max_for_level(level), do: max(level, 1) * 5

  def merge(existing, derived) do
    additions = derived |> Map.drop(Map.keys(existing)) |> Map.new(fn {id, entry} -> {id, Map.delete(entry, :slot)} end)
    existing |> with_slots() |> Map.merge(additions) |> with_slots()
  end

  def with_slots(skills) when is_map(skills) do
    used = MapSet.new(Map.values(skills), &Map.get(&1, :slot))

    skills
    |> Enum.sort_by(fn {id, _entry} -> id end)
    |> Enum.map_reduce(used, fn {id, entry}, occupied ->
      if is_integer(Map.get(entry, :slot)) do
        {{id, entry}, occupied}
      else
        slot = Enum.find(0..(@max_skill_entries - 1), &(not MapSet.member?(occupied, &1)))
        {{id, Map.put(entry, :slot, slot)}, MapSet.put(occupied, slot)}
      end
    end)
    |> elem(0)
    |> Map.new()
  end

  def forget(skills, ids, forgotten) do
    {Map.drop(skills, ids), Map.merge(forgotten, Map.take(skills, ids))}
  end

  def restore(skills, forgotten) do
    restored =
      Map.new(skills, fn {id, entry} ->
        case Map.get(forgotten, id) do
          %{value: value} -> {id, %{entry | value: min(max(entry.value, value), entry.max)}}
          _ -> {id, entry}
        end
      end)

    {restored, Map.drop(forgotten, Map.keys(skills))}
  end

  def new_entry(range, always_max?, level) do
    case range do
      :language -> %{value: 300, max: 300, range: range, always_max?: always_max?}
      :mono -> %{value: 1, max: 1, range: range, always_max?: always_max?}
      :level -> level_entry(always_max?, level)
    end
  end

  defp level_entry(always_max?, level) do
    max = max_for_level(level)
    value = if always_max?, do: max, else: 1
    %{value: value, max: max, range: :level, always_max?: always_max?}
  end

  def on_level_up(skills, level) when is_map(skills) do
    Map.new(skills, fn
      {id, %{range: :level} = entry} -> {id, level_up_entry(entry, level)}
      {id, entry} -> {id, entry}
    end)
  end

  def on_level_up(skills, _level), do: skills

  def max_out(skills) when is_map(skills) do
    Map.new(skills, fn
      {id, %{range: range} = entry} when range in [:level, :tier] -> {id, %{entry | value: entry.max}}
      {id, entry} -> {id, entry}
    end)
  end

  def max_out(skills), do: skills

  def max_professions(skills, cap \\ 300)

  def max_professions(skills, cap) when is_map(skills) and is_integer(cap) and cap > 0 do
    Map.new(skills, fn
      {id, %{range: :tier} = entry} -> {id, %{entry | value: cap, max: cap}}
      {id, entry} -> {id, entry}
    end)
  end

  def max_professions(skills, _cap), do: skills

  defp level_up_entry(entry, level) do
    max = max_for_level(level)
    value = if entry.always_max?, do: max, else: min(entry.value, max)
    %{entry | value: value, max: max}
  end

  def value(skills, skill_id, default \\ 0)

  def value(skills, skill_id, default) when is_map(skills) do
    case Map.get(skills, skill_id) do
      %{value: value} -> value
      _missing -> default
    end
  end

  def value(_skills, _skill_id, default), do: default

  def known?(skills, skill_id) when is_map(skills), do: Map.has_key?(skills, skill_id)
  def known?(_skills, _skill_id), do: false

  def learn_rank(skills, skill_id, skill_max)
      when is_map(skills) and is_integer(skill_id) and skill_id > 0 and is_integer(skill_max) and skill_max > 0 do
    skills = with_slots(skills)
    entry = Map.get(skills, skill_id, %{value: 1, max: skill_max, range: :tier, always_max?: false})
    entry = Map.put(entry, :step, max(Map.get(entry, :step, 0), div(skill_max, 75)))
    skills |> Map.put(skill_id, %{entry | max: max(entry.max, skill_max), range: :tier}) |> with_slots()
  end

  def learn_rank(skills, _skill_id, _skill_max), do: skills

  def rank_known?(skills, skill_id, skill_max) when is_map(skills) and is_integer(skill_max) and skill_max > 0 do
    case Map.get(skills, skill_id) do
      %{step: step} -> step >= div(skill_max, 75)
      _unknown -> false
    end
  end

  def rank_known?(_skills, _skill_id, _skill_max), do: false

  def encode(skills, bonuses \\ %{})

  def encode(skills, bonuses) when is_map(skills) do
    entries =
      skills
      |> with_slots()
      |> Enum.reject(fn {_id, entry} -> is_nil(entry.slot) end)
      |> Map.new(fn {id, entry} -> {entry.slot, encode_entry(id, entry, bonuses)} end)

    for slot <- 0..(@max_skill_entries - 1), into: <<>>, do: Map.get(entries, slot, <<0::size(96)>>)
  end

  def encode(_skills, _bonuses), do: nil

  defp encode_entry(id, entry, bonuses) do
    {temporary, permanent} = Map.get(bonuses, id, {0, 0})
    step = Map.get(entry, :step, 0)

    <<id::little-size(16), step::little-size(16), entry.value::little-size(16), entry.max::little-size(16),
      temporary::little-signed-size(16), permanent::little-signed-size(16)>>
  end

  def combat_skill_up(skills, skill_id, opts) when is_map(skills) do
    player_level = Keyword.fetch!(opts, :player_level)
    cap = max_for_level(player_level)

    with %{range: :level, always_max?: false, value: value} = entry when value < cap <- Map.get(skills, skill_id),
         chance = skill_up_chance(value, cap, player_level, opts),
         true <- roll(opts).(chance) do
      {:gained, Map.put(skills, skill_id, %{entry | value: value + 1})}
    else
      _no_gain -> :unchanged
    end
  end

  def combat_skill_up(_skills, _skill_id, _opts), do: :unchanged

  def fishing_skill_up(skills, opts \\ [])

  def fishing_skill_up(skills, opts) when is_map(skills) do
    with %{value: value, max: max} = entry when value < max <- Map.get(skills, @fishing_skill),
         chance = if(value < 75, do: 100.0, else: div(2500, value - 50) * 1.0),
         true <- roll(opts).(chance) do
      {:gained, Map.put(skills, @fishing_skill, %{entry | value: value + 1})}
    else
      _no_gain -> :unchanged
    end
  end

  def fishing_skill_up(_skills, _opts), do: :unchanged

  defp skill_up_chance(value, cap, player_level, opts) do
    if Keyword.get(opts, :defense?, false) do
      defense_chance(value, cap, player_level, Keyword.fetch!(opts, :mob_level))
    else
      weapon_chance(value, cap) + min(10.0, 0.02 * Keyword.get(opts, :intellect, 0))
    end
    |> min(100.0)
  end

  defp defense_chance(value, cap, player_level, mob_level) do
    mob_level = min(mob_level, player_level + 5)
    level_diff = max(mob_level - Experience.gray_level(player_level), 3)
    3 * level_diff * (cap - value) / player_level
  end

  defp weapon_chance(value, cap) do
    if cap * 0.9 > value do
      min(100.0, cap * 0.9 * 50 / max(value, 1))
    else
      chance = (0.5 - 0.0168966 * value * (300.0 / cap) + 0.0152069 * 300.0) * 100.0
      skill_diff = cap - value
      if skill_diff <= 3, do: chance * (0.5 / (4 - skill_diff)), else: chance
    end
  end

  defp roll(opts) do
    Keyword.get(opts, :roll, fn chance -> :rand.uniform() * 100.0 < chance end)
  end
end
