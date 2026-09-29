defmodule ThistleTea.Game.World.Entity.GameObject.SpellCast do
  @moduledoc "Resolves object-origin spells into per-effect deliveries and object actions."

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  def launch(object, spell, target_guid, opts \\ [])

  def launch(%GameObject{} = object, %Spell{effects: []}, _target_guid, _opts), do: object

  def launch(%GameObject{} = object, %Spell{} = spell, target_guid, opts) do
    selection = if is_integer(target_guid) and target_guid > 0, do: Target.unit(target_guid), else: Target.none()
    requirements = SpellRequirements.resolve_targets(object, spell, selection)

    with :ok <- LocationTargets.validate(spell, requirements.locations),
         :ok <- UnitTargets.validate(spell, requirements.units),
         :ok <- ObjectTargets.validate(spell, requirements.objects) do
      selection = LocationTargets.apply(selection, requirements.locations)

      plan =
        SpellTargetResolver.resolve_plan(object, spell, selection, requirements.units,
          triggered?: true,
          locations: requirements.locations
        )

      deliveries =
        Enum.map(UnitTargets.guids(plan), fn guid ->
          context = %{
            CastContext.from_caster(object, spell, guid)
            | caster_guid: Keyword.get(opts, :caster_guid, object.object.guid),
              caster_level: Keyword.get(opts, :level, 1),
              selected_target_guid: target_guid,
              destination_position: Target.ground_location(selection),
              effect_indices: UnitTargets.indices(plan, guid)
          }

          Effects.deliver_spell(guid, context, spell)
        end)

      targets = Enum.uniq(UnitTargets.guids(plan) ++ ObjectTargets.guids(requirements.objects))
      launch = Effects.spell_go(object.object.guid, spell.id, targets, selection)
      actions = ObjectTargets.actions(spell, requirements.objects)
      Effects.enqueue(object, [launch | deliveries ++ actions])
    else
      {:error, _reason} -> object
    end
  end
end
