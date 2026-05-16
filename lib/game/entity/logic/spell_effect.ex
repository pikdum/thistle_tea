defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World

  def receive(target, caster_guid, %Spell{} = spell) do
    target
    |> apply_damage_effects(caster_guid, spell)
    |> maybe_apply_auras(caster_guid, spell)
  end

  def receive(target, _caster_guid, _spell), do: target

  defp apply_damage_effects(target, caster_guid, %Spell{effects: effects} = spell) do
    Enum.reduce(effects, target, fn effect, state ->
      apply_damage_effect(state, caster_guid, spell, effect)
    end)
  end

  defp apply_damage_effect(state, caster_guid, spell, %Effect{type: :school_damage} = effect) do
    damage = Effect.damage_roll(effect)

    state
    |> Core.take_damage(damage)
    |> broadcast_spell_damage(caster_guid, spell, damage)
  end

  defp apply_damage_effect(state, _caster_guid, _spell, _effect), do: state

  defp maybe_apply_auras(target, caster_guid, %Spell{} = spell) do
    case Spell.aura_effects(spell) do
      [] -> target
      _ -> Aura.apply_spell(target, caster_guid, caster_level(target, caster_guid), spell)
    end
  end

  defp caster_level(%{unit: %{level: level}}, _caster_guid) when is_integer(level), do: level
  defp caster_level(_target, _caster_guid), do: 1

  defp broadcast_spell_damage(state, caster_guid, %Spell{} = spell, damage) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: caster_guid,
      target: state.object.guid,
      spell_id: spell.id,
      damage: damage,
      school: school_index(spell.school)
    }
    |> World.broadcast_packet(state)

    state
  end

  defp school_index(:physical), do: 0
  defp school_index(:holy), do: 1
  defp school_index(:fire), do: 2
  defp school_index(:nature), do: 3
  defp school_index(:frost), do: 4
  defp school_index(:shadow), do: 5
  defp school_index(:arcane), do: 6
  defp school_index(other) when is_integer(other), do: other
  defp school_index(_), do: 0
end
