defmodule ThistleTea.Game.World.Loader.Skill do
  @moduledoc """
  Derives a player's skill lines from known spells via SkillLineAbility and
  SkillRaceClassInfo, following vmangos: only race/class skill rewards
  (acquire method 2) are added, tiered skills (professions) are skipped, and
  the value range comes from the skill line category plus the always-max
  race/class flag.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]
  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Logic.Skills

  @acquire_race_or_class_skill 2

  @flag_always_max_value 0x10

  @category_armor 8
  @category_languages 10

  def initial_skills(spell_ids, race, class, level) when is_list(spell_ids) do
    race_mask = 1 <<< (race - 1)
    class_mask = 1 <<< (class - 1)

    spell_ids
    |> skill_line_ids(race_mask, class_mask)
    |> Enum.flat_map(&build_entry(&1, race_mask, class_mask, level))
    |> Map.new()
  end

  def initial_skills(_spell_ids, _race, _class, _level), do: %{}

  defp skill_line_ids([], _race_mask, _class_mask), do: []

  defp skill_line_ids(spell_ids, race_mask, class_mask) do
    DBC.all(
      from(s in SkillLineAbility,
        where: s.spell in ^spell_ids and s.acquire_method == @acquire_race_or_class_skill,
        where: s.race_mask == 0 or fragment("? & ?", s.race_mask, ^race_mask) != 0,
        where: s.class_mask == 0 or fragment("? & ?", s.class_mask, ^class_mask) != 0,
        select: s.skill_line,
        distinct: true
      )
    )
  end

  defp build_entry(skill_line, race_mask, class_mask, level) do
    with %SkillRaceClassInfo{skill_tier: 0} = info <- race_class_info(skill_line, race_mask, class_mask),
         %SkillLine{category: category} <- DBC.get(SkillLine, skill_line) do
      always_max? = (info.flags &&& @flag_always_max_value) != 0
      [{skill_line, Skills.new_entry(range(category), always_max?, level)}]
    else
      _skip -> []
    end
  end

  defp race_class_info(skill_line, race_mask, class_mask) do
    DBC.one(
      from(i in SkillRaceClassInfo,
        where: i.skill_line == ^skill_line,
        where: i.race_mask == 0 or fragment("? & ?", i.race_mask, ^race_mask) != 0,
        where: i.class_mask == 0 or fragment("? & ?", i.class_mask, ^class_mask) != 0,
        limit: 1
      )
    )
  end

  defp range(@category_armor), do: :mono
  defp range(@category_languages), do: :language
  defp range(_category), do: :level
end
