defmodule ThistleTea.Game.Spell.Combat do
  @moduledoc """
  Combat and concealment consequences of a resolved spell contact. Detection
  describes whether the recipient can perceive the caster before effects land.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  defstruct combat?: false, pvp?: false, break_stealth?: false, break_invisibility?: false

  @misses [:miss, :resist, :dodge, :parry, :block, :immune]

  def decide(%Spell{} = spell, %CastContext{} = context, outcome, detected?) do
    cond do
      not Spell.harmful?(spell) -> %__MODULE__{}
      outcome == :hit -> hit(spell, context, detected?)
      outcome in @misses -> miss(spell, context, detected?)
      true -> %__MODULE__{}
    end
  end

  def damage_contact?(%Spell{} = spell, periodic?, triggered_by_proc?) do
    cond do
      triggered_by_proc? and not Spell.attribute?(spell, :not_a_proc) -> false
      Enum.any?(spell.effects, &(&1.aura == :damage_shield)) -> false
      periodic? -> Spell.attribute?(spell, :channeled)
      true -> true
    end
  end

  def damage_contact?(_spell, periodic?, triggered_by_proc?), do: not periodic? and not triggered_by_proc?

  def apply_caster(entity, %Effects.SpellContact{decision: decision, now: now}) do
    if Death.alive?(entity) and not PlayerCombat.undetectable?(entity, now) do
      types =
        []
        |> maybe_type(decision.break_stealth?, :mod_stealth)
        |> maybe_type(decision.break_invisibility?, :mod_invisibility)

      {entity, events} = Aura.remove_aura_types(entity, types, now)
      entity = Effects.enqueue(entity, events)

      if decision.combat? and is_struct(entity, Character),
        do: PlayerCombat.mark_initiated(entity, now),
        else: entity
    else
      entity
    end
  end

  defp hit(spell, context, detected?) do
    if not Spell.family_flag?(spell, 8, 0x80) and (detected? or spell.id == 6358) do
      combat? = hit_combat?(spell, context)

      %__MODULE__{
        combat?: combat?,
        pvp?: combat? or Spell.attribute?(spell, :pvp_enabling),
        break_stealth?: combat? and not Spell.attribute?(spell, :allow_while_stealthed),
        break_invisibility?: combat? and not Spell.attribute?(spell, :allow_while_invisible)
      }
    else
      %__MODULE__{pvp?: not peaceful_only?(spell)}
    end
  end

  defp hit_combat?(spell, context),
    do:
      (active_cast?(context, spell) or direct_threat?(spell)) and Spell.starts_combat?(spell) and
        not Spell.attribute?(spell, :no_initial_threat)

  defp miss(spell, context, detected?) do
    breaks? = Spell.attribute?(spell, :failure_breaks_stealth)

    if detected? or breaks? do
      combat? = breaks? or (active_cast?(context, spell) and not Spell.attribute?(spell, :no_threat))
      %__MODULE__{combat?: combat?, pvp?: combat? or Spell.attribute?(spell, :pvp_enabling), break_stealth?: breaks?}
    else
      %__MODULE__{}
    end
  end

  defp active_cast?(context, spell), do: not context.triggered_by_aura? or spell.speed > 0

  defp direct_threat?(spell),
    do:
      Enum.any?(
        spell.effects,
        &(&1.type in [:modify_threat, :attack_me, 91] and is_number(&1.base_points) and &1.base_points > 0)
      )

  defp peaceful_only?(spell),
    do: Spell.attribute?(spell, :not_in_combat) and Spell.attribute?(spell, :only_peaceful_targets)

  defp maybe_type(types, true, type), do: [type | types]
  defp maybe_type(types, false, _type), do: types
end
