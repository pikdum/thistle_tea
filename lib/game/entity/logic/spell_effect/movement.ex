defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Movement do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Distraction
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Knockback
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def apply(state, %CastContext{caster_guid: guid}, _spell, %Effect{type: :bind}, _now) do
    {state, [%Effects.BindHome{binder_guid: guid}]}
  end

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

  def apply(state, %CastContext{}, %Spell{id: spell_id}, %Effect{type: :teleport_units} = effect, _now) do
    request =
      if :home_bind in [effect.implicit_target_a, effect.implicit_target_b],
        do: %Effects.TeleportHome{},
        else: Effects.teleport_to_spell_target(spell_id)

    {state, [request]}
  end

  def apply(
        %{unit: %Unit{}, internal: %Internal{world: world, taxi_flight: nil}} = state,
        %CastContext{caster_position: {world, _x, _y, _z}, caster_orientation: orientation} = context,
        %Spell{id: id},
        %Effect{type: :teleport_units_face_caster} = effect,
        _now
      )
      when is_number(orientation) do
    request = %Effects.TeleportNearCaster{
      caster_position: context.caster_position,
      caster_orientation: orientation,
      destination: teleport_destination(state, context, effect, id)
    }

    {state, [request]}
  end

  def apply(%Character{} = state, %CastContext{}, _spell, %Effect{type: :stuck}, _now) do
    case SafePosition.destination(state) do
      {_x, _y, _z, _orientation} = position -> {state, [Effects.teleport(position)]}
      nil -> {state, []}
    end
  end

  def apply(state, %CastContext{destination_position: destination}, _spell, %Effect{type: :distract} = effect, now) do
    Distraction.apply(state, destination, Effect.roll(effect, 0) * 1_000, now)
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :knockback} = effect, now) do
    vertical_speed = div(Amount.roll(spell, effect, context), 10) * 1.0
    Knockback.apply(state, context, (effect.misc_value || 0) / 10, vertical_speed, now)
  end

  def apply(state, %CastContext{} = context, _spell, %Effect{type: :player_pull} = effect, now) do
    Knockback.pull(state, context, max(effect.misc_value || 0, 1) / 10, now)
  end

  def apply(
        %Character{object: %{guid: guid}} = state,
        _context,
        %Spell{id: id},
        %Effect{type: :send_taxi, misc_value: path},
        _now
      )
      when is_integer(path) and path > 0 do
    {state, [%Effects.SendTaxiPath{target_guid: guid, path_id: path, spell_id: id}]}
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}

  defp teleport_destination(_state, %CastContext{destination_position: {x, y, z}}, _effect, _id),
    do: {:position, {x, y, z}}

  defp teleport_destination(state, context, effect, id) do
    selectors = [effect.implicit_target_a, effect.implicit_target_b]
    radius = max(effect.radius_yards || 0.0, 0.0)
    size = (state.unit.bounding_radius || Unit.default_bounding_radius()) + (context.caster_bounding_radius || 0.0)

    cond do
      17 in selectors ->
        {:database, id, radius + size}

      :caster_destination in selectors ->
        {_world, x, y, z} = context.caster_position
        {:position, {x, y, z}}

      47 in selectors ->
        {:forward, radius}

      true ->
        {:forward, radius + size}
    end
  end
end
