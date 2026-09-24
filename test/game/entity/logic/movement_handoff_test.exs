defmodule ThistleTea.Game.Entity.Logic.MovementHandoffTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.MovementHandoff
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "take/3" do
    test "consumes the previous controller's final snapshot once", %{entity: entity} do
      offered = MovementHandoff.offer(entity, 2, -10_000)
      assert {:error, ^offered} = MovementHandoff.take(offered, 3, -9_999)
      assert {:ok, consumed} = MovementHandoff.take(offered, 2, -9_999)
      assert consumed.internal.movement_handoff == nil
      assert {:error, ^consumed} = MovementHandoff.take(consumed, 2, -9_998)
    end

    test "rejects expiry, death, movement, and world changes", %{entity: entity} do
      offered = MovementHandoff.offer(entity, 2, -10_000)

      for {entity, now} <- [
            {offered, -6_000},
            {put_in(offered.unit.health, 0), -9_999},
            {put_in(offered.movement_block.position, {1.0, 0.0, 0.0, 0.0}), -9_999},
            {put_in(offered.internal.world, WorldRef.instance(451, 2)), -9_999},
            {put_in(offered.internal.movement_start_time, -9_999), -9_999}
          ] do
        assert {:error, rejected} = MovementHandoff.take(entity, 2, now)
        assert rejected.internal.movement_handoff == nil
      end
    end

    test "teleport invalidates a snapshot even when the destination is unchanged", %{entity: entity} do
      offered = MovementHandoff.offer(entity, 2, -10_000)
      {teleported, _projection} = Movement.teleport(offered, offered.movement_block.position, -9_999)
      assert teleported.internal.movement_handoff == nil
      assert {:error, ^teleported} = MovementHandoff.take(teleported, 2, -9_998)
    end
  end

  defp entity(_context) do
    %{
      entity: %Character{
        unit: %Unit{health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.instance(451, 1)}
      }
    }
  end
end
