defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Honor do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

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
