defmodule ThistleTea.Game.Entity.Logic.CoreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core

  describe "heal/2" do
    test "restores health up to max health" do
      entity = entity(health: 40, max_health: 100)

      entity = Core.heal(entity, 75)

      assert entity.unit.health == 100
      assert entity.internal.broadcast_update? == true
    end

    test "ignores non-positive amounts" do
      entity = entity(health: 40, max_health: 100)

      assert Core.heal(entity, 0) == entity
    end
  end

  describe "should_tether?/2" do
    test "returns true when outside tether range after timeout" do
      entity = entity(position: {100.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000)

      assert Core.should_tether?(entity, 7_000)
    end

    test "returns false inside tether range" do
      entity = entity(position: {10.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000)

      refute Core.should_tether?(entity, 7_000)
    end

    test "returns false before timeout" do
      entity = entity(position: {100.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000)

      refute Core.should_tether?(entity, 6_999)
    end
  end

  defp entity(opts) do
    %{
      unit: %Unit{
        health: Keyword.get(opts, :health),
        max_health: Keyword.get(opts, :max_health),
        level: 1
      },
      internal: %Internal{
        spawn: %Spawn{position: {0.0, 0.0, 0.0}},
        last_hostile_time: Keyword.get(opts, :last_hostile_time)
      },
      movement_block: %MovementBlock{position: Keyword.get(opts, :position)}
    }
  end
end
