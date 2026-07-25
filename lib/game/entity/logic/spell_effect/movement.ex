defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def apply(
        %{movement_block: %{position: {x, y, z, orientation}}} = state,
        %CastContext{},
        _spell,
        %Effect{type: :leap} = effect,
        _now
      ) do
    distance = if is_number(effect.radius_yards) and effect.radius_yards > 0, do: effect.radius_yards, else: 20.0
    destination = {x + :math.cos(orientation) * distance, y + :math.sin(orientation) * distance, z, orientation}
    {state, [Effects.leap(destination)]}
  end

  def apply(state, %CastContext{}, %Spell{id: spell_id}, %Effect{type: :teleport_units}, _now) do
    {state, [Effects.teleport_to_spell_target(spell_id)]}
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}
end
