defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet.Autocast do
  @moduledoc "Pet spell usefulness rules over the current owner state and immutable tick observations."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @stunned 0x00040000

  def allowed?(%{internal: %{pet: %Pet{autocast: enabled}}} = pet, %Spell{} = spell, target_guid, %Context{} = context) do
    target = target_snapshot(pet, target_guid, context)

    MapSet.member?(enabled, spell.id) and
      not Spell.attribute?(spell, :passive) and not Spell.attribute?(spell, :no_autocast_ai) and
      preserves_attack?(pet, spell) and combat_useful?(pet, spell) and
      shield_useful?(spell, target) and heal_useful?(spell, target) and
      auras_useful?(pet, spell, target, context)
  end

  def allowed?(_entity, _spell, _target_guid, _context), do: true

  defp preserves_attack?(pet, spell) do
    not has_victim?(pet) or not Spell.attribute?(spell, :cancels_auto_attack_combat)
  end

  defp combat_useful?(pet, spell) do
    Spell.harmful?(spell) or Spell.attribute?(spell, :not_in_combat) or
      has_victim?(pet) or not combat_only?(spell)
  end

  defp combat_only?(spell) do
    cond do
      fire_shield?(spell) -> false
      spell.spell_icon == 153 -> true
      Enum.any?(spell.effects, &(&1.type == :instakill or &1.aura == :mod_damage_done)) -> true
      true -> cooldown_exceeds_duration?(spell)
    end
  end

  defp cooldown_exceeds_duration?(%Spell{duration_ms: duration} = spell) when is_integer(duration) and duration >= 0 do
    max(spell.recovery_time_ms, spell.category_recovery_time_ms) > duration
  end

  defp cooldown_exceeds_duration?(_spell), do: false

  defp shield_useful?(spell, target) do
    not fire_shield?(spell) or Map.get(target, :attacker_count, 0) > 0
  end

  defp fire_shield?(%Spell{spell_visual: 289} = spell), do: Spell.family_flag?(spell, 5, 0x00800000)
  defp fire_shield?(_spell), do: false

  defp heal_useful?(spell, target) do
    not Spell.healing?(spell) or Map.get(target, :health_pct) != 100.0
  end

  defp auras_useful?(pet, spell, target, context) do
    Enum.any?(spell.effects, &(&1.type == :school_damage)) or
      Enum.all?(spell.effects, &aura_useful?(pet, spell, &1, target, context))
  end

  defp aura_useful?(pet, %Spell{stack_amount: stacks} = spell, %Effect{type: :apply_aura} = effect, target, context)
       when stacks <= 1 do
    not held?(spell, effect, target) and
      speed_useful?(pet, effect, context) and stun_useful?(effect, target)
  end

  defp aura_useful?(_pet, spell, %Effect{type: :apply_area_aura} = effect, target, _context) do
    not held?(spell, effect, target)
  end

  defp aura_useful?(_pet, _spell, _effect, _target, _context), do: true

  defp held?(spell, effect, target) do
    MapSet.member?(Map.get(target, :aura_effects, MapSet.new()), {spell.id, effect.index})
  end

  defp speed_useful?(pet, %Effect{aura: :mod_increase_speed}, context) do
    not Combat.in_combat_range?(pet, pet.internal.blackboard, context)
  end

  defp speed_useful?(_pet, _effect, _context), do: true

  defp stun_useful?(%Effect{aura: :mod_stun}, target), do: (Map.get(target, :unit_flags, 0) &&& @stunned) == 0
  defp stun_useful?(_effect, _target), do: true

  defp has_victim?(%{unit: %{target: target}}), do: is_integer(target) and target > 0

  defp target_snapshot(%{object: %{guid: guid}} = pet, guid, %Context{perception: perception}) do
    Map.merge(Perception.metadata(perception, guid) || %{}, %{
      aura_effects: Aura.effect_keys(pet),
      health_pct: Core.health_pct(pet),
      unit_flags: pet.unit.flags || 0
    })
  end

  defp target_snapshot(_pet, target, %Context{perception: perception}),
    do: Perception.metadata(perception, target) || %{}
end
