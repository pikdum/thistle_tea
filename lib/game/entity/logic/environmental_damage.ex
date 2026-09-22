defmodule ThistleTea.Game.Entity.Logic.EnvironmentalDamage do
  @moduledoc """
  Player environmental damage, including school mitigation, shield depletion,
  client feedback, and the shared health/death transition. Resistance uses the
  victim's own level; fall, drowning, and exhaustion bypass absorption.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.SpellResist

  @types [:exhaustion, :drowning, :fall, :lava, :slime, :fire]

  def apply(%Character{} = character, type, damage, now, opts \\ [])
      when type in @types and is_integer(damage) and damage >= 0 and is_integer(now) do
    school = school(type)

    if Death.alive?(character) and not character.internal.godmode and not DamageImmunity.immune?(character, school) do
      {character, remaining, absorbed, resisted} = mitigate(character, damage, school, now, opts)
      character = interrupt_stealth_and_sitting(character, now)

      character
      |> Effects.enqueue(%Effects.EnvironmentalDamage{
        type: type,
        damage: remaining,
        absorbed: absorbed,
        resisted: resisted
      })
      |> Core.take_damage(remaining, now, environmental?: true, school: school)
    else
      character
    end
  end

  defp school(type) when type in [:fire, :lava], do: :fire
  defp school(:slime), do: :nature
  defp school(_type), do: :physical

  defp mitigate(character, damage, :physical, _now, _opts), do: {character, damage, 0, 0}

  defp mitigate(character, damage, school, now, opts) do
    resistance = if school == :fire, do: character.unit.fire_resistance, else: character.unit.nature_resistance
    resistance = ResistancePenetration.resistance(resistance, ResistancePenetration.snapshot(character), school)

    resisted =
      SpellResist.resisted_amount(damage, resistance, character.unit.level, Keyword.put(opts, :target_creature?, false))

    {character, remaining} = Aura.absorb_damage(character, damage - resisted, school, now)
    {character, remaining, damage - resisted - remaining, resisted}
  end

  defp interrupt_stealth_and_sitting(character, now) do
    {character, events} = Aura.remove_aura_types(character, [:mod_stealth], now)
    character = Effects.enqueue(character, events)

    if character.unit.stand_state in [1, 3, 8] and not Aura.has_aura?(character, :mounted),
      do: Emote.move(character, false, true, now),
      else: character
  end
end
