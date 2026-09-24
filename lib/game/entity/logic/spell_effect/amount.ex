defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Amount do
  @moduledoc false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Chain
  alias ThistleTea.Game.Spell.Effect

  def roll(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    effect
    |> Effect.roll(Spell.level_units(spell, context.caster_level))
    |> Chain.scale(effect, context)
  end
end
