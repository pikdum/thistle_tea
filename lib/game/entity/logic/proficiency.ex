defmodule ThistleTea.Game.Entity.Logic.Proficiency do
  @moduledoc """
  Equipment capabilities derived from a character's spellbook and skills:
  proficiency spell effects grant subclass-mask bits per item class, which
  gate equipping weapons and armor, while skill values enforce item-template
  requirements. Fishing grants the fishing-pole subclass bit directly because
  vanilla has no separate fishing-pole proficiency spell.
  """
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell, as: SpellData
  alias ThistleTea.Game.Spell.Effect

  defstruct weapon_mask: 0, armor_mask: 0, skill_values: %{}, dual_wield?: false

  @item_class_weapon 2
  @item_class_armor 4

  @fishing_pole_subclass 20

  @unskilled_weapon_subclasses [9, 11, 12, 14]
  @unskilled_armor_subclasses [0, 5, 7, 8, 9]

  def item_class_weapon, do: @item_class_weapon
  def item_class_armor, do: @item_class_armor

  def all, do: %__MODULE__{weapon_mask: -1, armor_mask: -1, skill_values: :all, dual_wield?: true}

  def from_character(%Character{player: player, internal: internal}) do
    skills = player.skills || %{}

    internal.spellbook
    |> from_spellbook()
    |> put_skills(skills)
  end

  def from_spellbook(spellbook) when is_map(spellbook) do
    Enum.reduce(spellbook, %__MODULE__{}, fn {_id, %SpellData{} = spell}, acc ->
      Enum.reduce(spell.effects, acc, &apply_effect(&2, &1, spell))
    end)
  end

  def from_spellbook(_spellbook), do: %__MODULE__{}

  defp apply_effect(%__MODULE__{} = prof, %Effect{type: :proficiency}, %SpellData{} = spell) do
    mask = spell.equipped_item_subclass_mask

    case spell.equipped_item_class do
      @item_class_weapon -> %{prof | weapon_mask: prof.weapon_mask ||| mask}
      @item_class_armor -> %{prof | armor_mask: prof.armor_mask ||| mask}
      _other -> prof
    end
  end

  defp apply_effect(%__MODULE__{} = prof, %Effect{type: :dual_wield}, _spell) do
    %{prof | dual_wield?: true}
  end

  defp apply_effect(%__MODULE__{} = prof, _effect, _spell), do: prof

  def can_equip?(%__MODULE__{} = prof, %ItemTemplate{} = template) do
    with :ok <- check_required_skill(prof, template) do
      check_item_class(prof, template)
    end
  end

  defp check_item_class(%__MODULE__{} = prof, %ItemTemplate{class: @item_class_weapon, subclass: subclass})
       when subclass not in @unskilled_weapon_subclasses do
    check_mask(prof.weapon_mask, subclass)
  end

  defp check_item_class(%__MODULE__{} = prof, %ItemTemplate{class: @item_class_armor, subclass: subclass})
       when subclass not in @unskilled_armor_subclasses do
    check_mask(prof.armor_mask, subclass)
  end

  defp check_item_class(%__MODULE__{}, %ItemTemplate{}), do: :ok

  defp put_skills(%__MODULE__{} = prof, skills) do
    weapon_mask =
      if Skills.known?(skills, Skills.fishing_skill()) do
        prof.weapon_mask ||| 1 <<< @fishing_pole_subclass
      else
        prof.weapon_mask
      end

    skill_values = Map.new(skills, fn {skill_id, entry} -> {skill_id, entry.value} end)
    %{prof | weapon_mask: weapon_mask, skill_values: skill_values}
  end

  defp check_required_skill(%__MODULE__{skill_values: :all}, %ItemTemplate{}), do: :ok

  defp check_required_skill(%__MODULE__{skill_values: skill_values}, %ItemTemplate{
         required_skill: skill_id,
         required_skill_rank: rank
       })
       when is_integer(skill_id) and skill_id > 0 and is_integer(rank) and rank > 0 do
    if Map.get(skill_values, skill_id, 0) >= rank, do: :ok, else: {:error, :no_required_proficiency}
  end

  defp check_required_skill(%__MODULE__{}, %ItemTemplate{}), do: :ok

  defp check_mask(mask, subclass) do
    if (mask &&& 1 <<< subclass) == 0, do: {:error, :no_required_proficiency}, else: :ok
  end
end
