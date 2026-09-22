defmodule ThistleTea.Game.Entity.Logic.Aura.ProcDamage do
  @moduledoc """
  Prepares direct damage from a proc aura using its carrier's current spell
  inputs and the original effect's dice and coefficient.
  """

  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.MechanicResistance
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Semantics

  def prepare(carrier, %Spell{} = spell, effect_index, target_guid) do
    case Enum.find(spell.effects, &(&1.index == effect_index and &1.aura == :proc_trigger_damage)) do
      %Effect{} = effect ->
        effect = %{
          effect
          | type: :school_damage,
            semantic: nil,
            aura: nil,
            bonus_coefficient: Coefficient.value(spell, effect, :direct),
            implicit_target_a: :target_enemy,
            implicit_target_b: nil,
            trigger_spell_id: nil
        }

        attributes = spell.attributes |> MapSet.put(:cant_crit) |> MapSet.put(:no_reflection)
        damage_spell = Semantics.compile(%{spell | effects: [effect], attributes: attributes, semantics: nil, speed: 0})

        context = %{
          CastContext.from_caster(carrier, damage_spell, target_guid)
          | proc_damage?: true,
            target_hostile?: true
        }

        {damage_spell, context}

      _effect ->
        nil
    end
  end

  def hit?(carrier, spell, target, target_player?, opts \\ [])

  def hit?(carrier, %Spell{dmg_class: 1} = spell, target, target_player?, opts) do
    if Spell.harmful?(spell) do
      target_bonus = Aura.versus_amount(Map.get(target, :attacker_spell_hit_chance), Spell.school_mask(spell))

      hit_bonus =
        Aura.flat_amount(carrier, :mod_spell_hit_chance) +
          Modifiers.value(carrier, spell, :resist_miss_chance, 0) + target_bonus

      SpellResist.magic_hit?(
        carrier.unit.level || 1,
        Map.get(target, :level) || 1,
        target_player?,
        Keyword.merge(opts,
          hit_bonus: hit_bonus,
          mechanic_resistance: MechanicResistance.chance(Map.get(target, :mechanic_resistance), spell.mechanic)
        )
      )
    else
      true
    end
  end

  def hit?(_carrier, _spell, _target, _target_player?, _opts), do: true
end
