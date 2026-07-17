defmodule ThistleTea.Game.Entity.Server.GameObject.Trap do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Component.Internal.Trap
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.World

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
end
