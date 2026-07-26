defmodule ThistleTea.Game.Entity.EffectResolver.Combat do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @drop_threat_radius 250

  def resolve(%Character{} = entity, %Effects.DropNearbyThreat{}) do
    target_guids =
      entity
      |> World.nearby_mobs(@drop_threat_radius)
      |> Enum.map(&elem(&1, 0))

    [Effects.drop_nearby_threat_resolved(target_guids, StealthDetection.target_metadata(entity))]
  end

  def resolve(_entity, %Effects.DropNearbyThreat{}), do: []

  def resolve(%Character{} = entity, %Effects.BladeFlurry{} = effect) when is_integer(effect.spell_id) do
    resolve_secondary(entity, effect.target_guid, effect.damage, effect.spell_id, Scripts.blade_flurry_radius_yards())
  end

  def resolve(_entity, %Effects.BladeFlurry{}), do: []

  def resolve(%Character{} = entity, %Effects.SecondaryMelee{} = effect) do
    resolve_secondary(entity, effect.target_guid, effect.damage, effect.spell_id, effect.range_yards)
  end

  def resolve(_entity, %Effects.SecondaryMelee{}), do: []

  defp resolve_secondary(entity, primary, damage, spell_id, radius) do
    secondary =
      entity
      |> SpellTargetResolver.resolve_query({:caster_aoe, radius})
      |> Enum.reject(&(&1 == primary))
      |> random_target()

    with secondary when is_integer(secondary) <- secondary,
         %Spell{} = spell <- SpellLoader.load(spell_id),
         %Spell.Effect{} = effect <- List.first(Spell.damage_effects(spell)) do
      spell = %{spell | effects: [%{effect | base_points: damage, die_sides: 0, base_dice: 0}]}
      context = CastContext.from_caster(entity, spell, secondary)
      [Spells.resolved_delivery(entity, Effects.deliver_spell(secondary, context, spell))]
    else
      _missing -> []
    end
  end

  defp random_target([]), do: nil
  defp random_target(targets), do: Enum.random(targets)
end
