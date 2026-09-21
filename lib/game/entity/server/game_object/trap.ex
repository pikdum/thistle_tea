defmodule ThistleTea.Game.Entity.Server.GameObject.Trap do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Component.Internal.Trap
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def target(%GameObject{internal: %{trap: %Trap{radius: radius}}}) when not is_number(radius) or radius <= 0, do: nil

  def target(%GameObject{
        internal: %{world: world, trap: %Trap{owner_guid: nil, radius: radius}},
        movement_block: %{position: {x, y, z, _o}}
      }) do
    :players
    |> World.nearby_units_exact(world, {x, y, z}, radius)
    |> Enum.map(&elem(&1, 0))
    |> Enum.find(&match?(%{alive?: true}, Metadata.query(&1, [:alive?])))
  end

  def target(%GameObject{
        internal: %{world: world, trap: %Trap{owner_guid: owner_guid, radius: radius}},
        movement_block: %{position: {x, y, z, _o}}
      }) do
    source = %{object: %{guid: owner_guid}}

    ((:mobs |> World.nearby_units_exact(world, {x, y, z}, radius)) ++
       (:players |> World.nearby_units_exact(world, {x, y, z}, radius)))
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 == owner_guid))
    |> Enum.find(&Hostility.valid_attack_target?(source, &1))
  end

  def target(_state), do: nil

  def consume(%Trap{charges: 1}), do: :depleted

  def consume(%Trap{charges: charges} = trap) when is_integer(charges) and charges > 1,
    do: %{trap | charges: charges - 1}

  def consume(%Trap{} = trap), do: trap

  def ready?(%Trap{depleted?: true}, _now), do: false
  def ready?(%Trap{ready_at: nil}, _now), do: true
  def ready?(%Trap{ready_at: ready_at}, now), do: now >= ready_at
end
