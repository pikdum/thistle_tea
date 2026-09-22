defmodule ThistleTea.Game.Entity.Logic.Knockback do
  @moduledoc """
  Launches client-controlled units away from or toward a spell's caster, retaining client
  collision and flight handling while interrupting authoritative casts.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext

  @gravity 19.29110527038574

  def apply(entity, %CastContext{} = context, horizontal_speed, vertical_speed, now) do
    {entity, removed} = Aura.remove_spells(entity, [24_778], now)

    {entity, events} = launch(entity, direction(entity, context), horizontal_speed, vertical_speed, now)
    {entity, removed ++ events}
  end

  def pull(
        %{
          object: %{guid: guid},
          unit: %Unit{} = unit,
          internal: %{world: world},
          movement_block: %{position: {x, y, z, _}}
        } = entity,
        %CastContext{caster_guid: caster_guid, caster_position: {world, cx, cy, cz}} = context,
        horizontal_speed,
        now
      )
      when guid != caster_guid and is_number(horizontal_speed) and horizontal_speed > 0 do
    radius = (unit.bounding_radius || Unit.default_bounding_radius()) + (context.caster_bounding_radius || 0.0)
    distance = :math.sqrt((cx - x) * (cx - x) + (cy - y) * (cy - y)) - radius

    if distance >= 0.1 do
      flight_time = distance / horizontal_speed
      vertical_speed = (cz - z) / flight_time + @gravity * flight_time / 2
      launch(entity, :math.atan2(cy - y, cx - x), horizontal_speed, vertical_speed, now)
    else
      {entity, []}
    end
  end

  def pull(entity, _context, _horizontal_speed, _now), do: {entity, []}

  defp launch(entity, angle, horizontal_speed, vertical_speed, now) do
    if movable?(entity) and is_number(angle) do
      entity = entity |> interrupt_cast(now) |> AutoRepeat.interrupt(now) |> Falling.reset()

      event = %Effects.Knockback{
        cos_angle: :math.cos(angle),
        sin_angle: :math.sin(angle),
        horizontal_speed: horizontal_speed,
        vertical_speed: vertical_speed
      }

      events = if client_controlled?(entity), do: [event], else: []
      {entity, events}
    else
      {entity, []}
    end
  end

  defp movable?(%Character{} = entity), do: unrestricted?(entity) and is_nil(entity.internal.taxi_flight)
  defp movable?(%Mob{} = entity), do: unrestricted?(entity)
  defp movable?(_entity), do: false

  defp client_controlled?(%Character{}), do: true
  defp client_controlled?(%Mob{internal: %{pet: %Pet{possessed?: true}}}), do: true
  defp client_controlled?(_entity), do: false

  defp unrestricted?(entity) do
    Death.alive?(entity) and is_nil(entity.internal.movement_start_time) and
      not ControlMovement.active?(entity) and not Aura.has_aura?(entity, :mod_root) and
      not Aura.has_aura?(entity, :mod_stun)
  end

  defp direction(%{object: %{guid: guid}, movement_block: %{position: {_, _, _, o}}}, %CastContext{caster_guid: guid}),
    do: o + :math.pi()

  defp direction(%{internal: %{world: world}, movement_block: %{position: {x, y, _, _}}}, %CastContext{
         caster_position: {world, cx, cy, _}
       }), do: :math.atan2(y - cy, x - cx)

  defp direction(_entity, _context), do: nil

  defp interrupt_cast(%{internal: %{casting: %Cast{phase: phase} = cast}} = entity, now)
       when phase in [:preparing, :channel_tick] do
    entity
    |> Effects.enqueue(Effects.spell_cast_failed(Cast.spell_id(cast), :interrupted))
    |> Casting.cancel(now)
  end

  defp interrupt_cast(entity, _now), do: entity
end
