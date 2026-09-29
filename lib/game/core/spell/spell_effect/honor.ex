defmodule ThistleTea.Game.Core.Spell.SpellEffect.Honor do
  @moduledoc false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Honor.Award
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect

  def apply(%Character{} = character, %CastContext{}, %Spell{}, %Effect{type: :honor} = effect, _now) do
    points = Effect.roll(effect, 0)

    effects =
      if points > 0 do
        [%Effects.HonorAward{target_guid: character.object.guid, award: %Award{type: :quest, points: points}}]
      else
        []
      end

    {character, effects}
  end

  def apply(entity, %CastContext{}, %Spell{}, %Effect{}, _now), do: {entity, []}
end
