defmodule ThistleTea.Game.Entity.Logic.PetResurrection do
  @moduledoc "Pet corpse lifetime and resurrection without replacing the pet's identity or progress."

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Spell.CastContext

  @stunned 0x00040000
  @skinnable 0x04000000

  def resurrectable_kind?(kind), do: kind in [:hunter, :summon, :guardian, :creature_pet]

  def prepare_corpse(%Mob{internal: %{pet: %Pet{} = pet} = internal, unit: unit} = entity) do
    pet = %{pet | corpse_generation: pet.corpse_generation + 1}
    unit = %{unit | dynamic_flags: 0, flags: ((unit.flags || 0) &&& bnot(@skinnable)) ||| @stunned}
    %{entity | unit: unit, internal: %{internal | pet: pet}}
  end

  def corpse_delay(%Mob{internal: %{guardian: %{corpse_delay_ms: delay}}}), do: delay
  def corpse_delay(%Mob{internal: %{pet: %Pet{kind: :hunter}}}), do: 3_600_000

  def corpse_delay(%Mob{internal: %{pet: %Pet{kind: kind}}}) when kind in [:summon, :guardian, :creature_pet],
    do: 15_000

  def corpse_delay(_entity), do: 100

  def corpse_expired?(
        %Mob{internal: %{pet: %Pet{corpse_generation: generation}, death_finalized?: true}} = entity,
        generation
      ), do: Core.dead?(entity)

  def corpse_expired?(_entity, _generation), do: false

  def revive(
        %Mob{internal: %{world: world, pet: %Pet{kind: kind, broken?: false}}} = entity,
        %CastContext{caster_position: {world, x, y, z}, caster_orientation: orientation},
        health,
        now
      )
      when is_number(orientation) do
    if resurrectable_kind?(kind) and Core.dead?(entity) do
      %{entity: entity} = Engagement.leave(entity, :resurrection)

      unit = %{
        entity.unit
        | health: health |> max(1) |> min(entity.unit.max_health),
          dynamic_flags: 0,
          flags: (entity.unit.flags || 0) &&& bnot(@stunned ||| @skinnable)
      }

      internal = %{entity.internal | death_finalized?: false, killed_by: nil}
      entity = %{entity | unit: unit, internal: internal} |> PetTraining.restore_passives(now)
      {entity, transition} = Movement.teleport(entity, {x, y, z, orientation}, now)

      events = [
        Effects.creature_teleported(
          world,
          transition.from_position,
          transition.position,
          transition.movement_block,
          0,
          world.map_id,
          0
        ),
        %Effects.PetRevived{
          source_guid: entity.object.guid,
          target_guid: entity.internal.pet.owner_guid,
          health: entity.unit.health
        }
      ]

      {Core.mark_broadcast_update(entity), events}
    else
      {entity, []}
    end
  end

  def revive(entity, _context, _health, _now), do: {entity, []}
end
