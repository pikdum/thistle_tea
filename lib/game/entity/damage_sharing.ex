defmodule ThistleTea.Game.Entity.DamageSharing do
  @moduledoc """
  Observes live damage-sharing recipients at the damage boundary and accepts
  transfers only in the recipient's current world.
  """

  alias ThistleTea.Game.Entity.Logic.DamageSharing, as: Logic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def targets(%{internal: %{world: world}} = entity) do
    entity
    |> Logic.casters()
    |> Enum.filter(fn guid ->
      match?(%{alive?: true}, Metadata.query(guid, [:alive?])) and
        match?({^world, _, _, _}, World.position(guid))
    end)
    |> MapSet.new()
  end

  def receive(%{internal: %{world: world}} = entity, %Effects.SharedDamage{world: world} = transfer, now),
    do: Logic.receive(entity, transfer, now)

  def receive(entity, %Effects.SharedDamage{}, _now), do: entity
end
