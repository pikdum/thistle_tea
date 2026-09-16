defmodule ThistleTea.Game.Player.Movement do
  @moduledoc """
  Translates client movement events into character movement rules.
  """
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_FALL_LAND, :MSG_MOVE_START_SWIM]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Pathfinding

  def apply_environment(%Character{} = character, opcode, now) do
    character
    |> Falling.update(action(opcode), now)
    |> Breathing.update(
      liquid_surface(character),
      now,
      :rand.uniform(max(character.unit.level || 1, 1)) - 1,
      body_height(character)
    )
  end

  def body_height(%Character{} = character), do: ModelGeometry.height(character.unit.display_id)
  def body_height(_entity), do: 2.0

  def liquid_surface(%Character{} = character) do
    {x, y, z, _} = character.movement_block.position
    Pathfinding.query_liquid_surface(character.internal.world.map_id, {x, y, z})
  end

  def publish_changes(%{character: %Character{internal: %{broadcast_update?: true}}} = state) do
    PlayerServer.maybe_broadcast_update(state)
  end

  def publish_changes(state), do: state

  defp action(@msg_move_fall_land), do: :land
  defp action(@msg_move_start_swim), do: :swim
  defp action(_opcode), do: :move
end
