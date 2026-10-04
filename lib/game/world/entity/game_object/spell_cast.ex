defmodule ThistleTea.Game.World.Entity.GameObject.SpellCast do
  @moduledoc """
  Resolves object-origin spells into per-effect deliveries and object actions.
  An object casts at its own level, as vmangos `GameObject::GetLevel` reports
  it: the level it was given, else the level cap. Harmful magic rolls the
  spell hit table against each target the way any caster's does, so a
  hunter's trap can be resisted.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.SpellResist
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  @max_level 60

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
          base = CastContext.from_caster(object, spell, guid)

          context = %{
            base
            | caster_guid: Keyword.get(opts, :caster_guid, object.object.guid),
              caster_level: Keyword.get_lazy(opts, :level, fn -> level(object) end),
              selected_target_guid: target_guid,
              destination_position: Target.ground_location(selection),
              effect_indices: UnitTargets.indices(plan, guid),
              rolls: Keyword.get(opts, :rolls, base.rolls)
          }

          Effects.deliver_spell(guid, %{context | hit_outcome: hit_outcome(object, spell, context, guid)}, spell)
        end)

      targets = Enum.uniq(UnitTargets.guids(plan) ++ ObjectTargets.guids(requirements.objects))
      launch = Effects.spell_go(object.object.guid, spell.id, targets, selection)
      actions = ObjectTargets.actions(spell, requirements.objects)
      Effects.enqueue(object, [launch | deliveries ++ actions])
    else
      {:error, _reason} -> object
    end
  end

  defp level(%GameObject{game_object: %{level: level}}) when is_integer(level) and level > 0, do: level
  defp level(%GameObject{}), do: @max_level

  defp hit_outcome(object, %Spell{dmg_class: 1} = spell, %CastContext{} = context, guid) do
    with true <- Spell.harmful?(spell),
         %{} = defense <- SpellTargetResolver.hit_defense(object, guid),
         roll = Rolls.integer(context.rolls, :spell_hit, 0, 9_999),
         false <- SpellResist.context_hit?(context, spell, defense, Guid.entity_type(guid) == :player, roll: roll) do
      :resist
    else
      _hit -> :hit
    end
  end

  defp hit_outcome(_object, _spell, _context, _guid), do: :hit
end
