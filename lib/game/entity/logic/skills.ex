defmodule ThistleTea.Game.Entity.Logic.Skills do
  @moduledoc """
  Player skill lines as data: a map of skill id to `%{value, max, range,
  always_max?}` entries, encoded into the PLAYER_SKILL_INFO update field.
  Ranges follow vmangos: `:level` skills cap at 5 x level and gain points
  from combat use, `:mono` skills stay 1/1, `:language` skills stay 300/300.
  """
  alias ThistleTea.Game.Entity.Logic.Experience

  @max_skill_entries 128

  @defense_skill 95
  @unarmed_skill 162

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
  def unarmed_skill, do: @unarmed_skill

  def weapon_skill_for_subclass(subclass), do: Map.get(@weapon_subclass_skills, subclass)

  def max_for_level(level), do: max(level, 1) * 5

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

  def encode(skills) when is_map(skills) and map_size(skills) > 0 do
    entries =
      skills
      |> Enum.sort_by(fn {id, _entry} -> id end)
      |> Enum.take(@max_skill_entries)
      |> Enum.map(fn {id, entry} ->
        <<id::little-size(32), entry.value::little-size(16), entry.max::little-size(16), 0::size(32)>>
      end)
      |> IO.iodata_to_binary()

    padding = @max_skill_entries * 12 - byte_size(entries)
    entries <> <<0::size(padding * 8)>>
  end

  def encode(_skills), do: nil

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
