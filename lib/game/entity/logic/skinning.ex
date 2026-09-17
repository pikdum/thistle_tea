defmodule ThistleTea.Game.Entity.Logic.Skinning do
  @moduledoc """
  Skinning admission, corpse flags, attempt difficulty, and profession gains.
  The corpse owner claims each skin once; this module only evaluates data.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  @skill 393
  @skinnable 0x04000000

  def skill_id, do: @skill
  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :skinning))

  def skill(%Character{} = character) do
    bonus =
      [:mod_skill, :mod_skill_talent]
      |> Enum.flat_map(&Aura.auras_of_type(character, &1))
      |> Enum.filter(&(&1.misc_value == @skill and is_integer(&1.amount)))
      |> Enum.reduce(0, &(&1.amount + &2))

    Skills.value(character.player.skills, @skill) + bonus
  end

  def validate(caster, %Spell{} = spell, target, opts) do
    if spell?(spell) do
      with :ok <- validate_target(target, skill(caster)),
           true <- Skills.known?(caster.player.skills, @skill) do
        check_tool(Keyword.get(opts, :count_item))
      else
        false -> {:error, :low_castlevel}
        error -> error
      end
    else
      :ok
    end
  end

  def validate_target(%{guid: guid} = target, skill) when is_integer(guid) do
    cond do
      not wild_creature?(target) -> {:error, :bad_targets}
      Map.get(target, :alive?) != false -> {:error, :target_not_dead}
      not has_skin?(target) -> {:error, :target_unskinnable}
      Map.get(target, :body_loot?, true) -> {:error, :target_not_looted}
      skill < 1 or required_skill(Map.get(target, :level, 1), skill) > skill -> {:error, :low_castlevel}
      true -> :ok
    end
  end

  def validate_target(_target, _skill), do: {:error, :bad_targets}

  defp wild_creature?(%{guid: guid} = target) do
    Guid.entity_type(guid) == :mob and Map.get(target, :owner_guid) in [nil, 0]
  end

  defp has_skin?(target) do
    id = Map.get(target, :skinning_id)
    is_integer(id) and id > 0 and Map.get(target, :skinned?) != true
  end

  def projection(%Mob{} = mob) do
    loot = mob.internal.loot

    %{
      guid: mob.object.guid,
      alive?: not Core.dead?(mob),
      owner_guid: mob.unit.summoned_by,
      level: mob.unit.level,
      skinning_id: if(loot, do: loot.skinning_id),
      skinned?: loot && (loot.skinned? or loot.corpse_removed?),
      body_loot?: loot && not is_nil(loot.session)
    }
  end

  def sync(%Mob{} = mob) do
    target = projection(mob)
    available? = validate_target(target, 10_000) == :ok and is_nil(mob.internal.pet)
    flags = (mob.unit.flags || 0) &&& bnot(@skinnable)
    flags = if available?, do: flags ||| @skinnable, else: flags
    if flags == 0 and is_nil(mob.unit.flags), do: mob, else: %{mob | unit: %{mob.unit | flags: flags}}
  end

  def required_skill(level, skill) when skill < 100, do: max((level - 10) * 10, 0)
  def required_skill(level, _skill), do: level * 5

  def attempt?(level, skill, roll), do: skill >= 300 or required_skill(level, skill) <= roll

  def skill_up(skills, level, rank, roll) do
    with %{value: value, max: cap} = entry when value < cap <- Map.get(skills, @skill),
         true <- roll < gain_chance(value, level, rank) do
      {:gained, Map.put(skills, @skill, %{entry | value: value + 1})}
    else
      _ -> :unchanged
    end
  end

  def gain_chance(value, level, rank) do
    required = if level < 20, do: max((level - 10) * 10, 0), else: level * 5

    chance =
      cond do
        value >= required + 100 -> 0
        value >= required + 50 -> 25
        value >= required + 25 -> 75
        true -> 100
      end

    multiplier = if Experience.elite_rank?(rank), do: 2, else: 1
    min(chance * multiplier / (1 <<< div(value, 75)), 100)
  end

  defp check_tool(count_item) when is_function(count_item, 1) do
    if Enum.any?([7005, 12_709, 19_901], &(count_item.(&1) > 0)), do: :ok, else: {:error, :equipped_item}
  end

  defp check_tool(_count_item), do: {:error, :equipped_item}
end
