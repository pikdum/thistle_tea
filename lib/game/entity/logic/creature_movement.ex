defmodule ThistleTea.Game.Entity.Logic.CreatureMovement do
  @moduledoc "Derives creature habitat capabilities and idle flight paths from template and ownership state."

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.CreatureFlags

  @inhabit_ground 1
  @inhabit_water 2
  @inhabit_air 4
  @flight_flags 0x01800000

  def can_fly?(%{internal: %Internal{pet: %Pet{kind: kind}}}) when kind in [:hunter, :summon], do: false

  def can_fly?(%{internal: %Internal{creature: %Creature{inhabit_type: inhabit_type}}}) when is_integer(inhabit_type),
    do: (inhabit_type &&& @inhabit_air) != 0

  def can_fly?(_entity), do: false

  def can_walk?(%{internal: %Internal{pet: %Pet{kind: kind}}}) when kind in [:hunter, :summon], do: true

  def can_walk?(%{internal: %Internal{creature: %Creature{inhabit_type: inhabit_type}}}) when is_integer(inhabit_type),
    do: (inhabit_type &&& @inhabit_ground) != 0

  def can_walk?(_entity), do: true

  def can_swim?(%{internal: %Internal{pet: %Pet{kind: kind}}}) when kind in [:hunter, :summon], do: true

  def can_swim?(%{internal: %Internal{creature: %Creature{inhabit_type: inhabit_type}}}) when is_integer(inhabit_type),
    do: (inhabit_type &&& @inhabit_water) != 0

  def can_swim?(_entity), do: true

  def swims?(entity), do: can_swim?(entity) and CreatureFlags.has?(entity, :can_swim)

  def accessible?(_entity, nil), do: true
  def accessible?(entity, true), do: can_swim?(entity)
  def accessible?(entity, false), do: can_walk?(entity) or can_fly?(entity)

  def path_options(%{internal: %Internal{creature: %Creature{inhabit_type: inhabit_type}}} = entity)
      when is_integer(inhabit_type) do
    [can_walk?: can_walk?(entity), can_swim?: can_swim?(entity), swim_animation?: swims?(entity)]
  end

  def path_options(_entity), do: []

  def always_run?(%{internal: %Internal{creature: %Creature{extra_flags: flags}}}) when is_integer(flags),
    do: (flags &&& 0x40) != 0

  def always_run?(_entity), do: false

  def flying?(%{unit: %{health: health}} = entity) when is_number(health) and health > 0, do: can_fly?(entity)
  def flying?(_entity), do: false

  def sync(%{internal: %Internal{creature: %Creature{}}, movement_block: %MovementBlock{} = movement} = entity) do
    flags = (movement.movement_flags || 0) &&& bnot(@flight_flags)
    flags = if flying?(entity), do: flags ||| @flight_flags, else: flags
    %{entity | movement_block: %{movement | movement_flags: flags}}
  end

  def sync(entity), do: entity

  def circle({x, y, z}, radius, {sx, sy, _sz}) when is_number(radius) and radius > 0 do
    count = radius |> Kernel.*(2) |> ceil() |> max(8) |> min(256)
    angle = :math.atan2(sy - y, sx - x)

    for index <- 1..count do
      bearing = angle + index * 2 * :math.pi() / count
      {x + radius * :math.cos(bearing), y + radius * :math.sin(bearing), z}
    end
  end

  def circle(_anchor, _radius, _position), do: []
end
