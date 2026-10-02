defmodule ThistleTea.Game.World.AreaTriggerCooldownTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.AreaTriggerCooldown
  alias ThistleTea.Test.Unique

  setup do
    table = :ets.new(:area_trigger_cooldown_test, [:public])
    %{table: table, trigger: %{id: Unique.integer(), cooldown_ms: 30_000}}
  end

  describe "claim/4" do
    test "rests a trigger for its cooldown once it fires", %{table: table, trigger: trigger} do
      world = WorldRef.open(0)

      assert AreaTriggerCooldown.claim(world, trigger, 1_000, table)
      refute AreaTriggerCooldown.claim(world, trigger, 30_999, table)
      assert AreaTriggerCooldown.claim(world, trigger, 31_000, table)
      refute AreaTriggerCooldown.claim(world, trigger, 31_001, table)
    end

    test "rests separately in each copy of a map", %{table: table, trigger: trigger} do
      assert AreaTriggerCooldown.claim(WorldRef.instance(329, 1), trigger, 0, table)
      assert AreaTriggerCooldown.claim(WorldRef.instance(329, 2), trigger, 0, table)
      refute AreaTriggerCooldown.claim(WorldRef.instance(329, 1), trigger, 0, table)
    end

    test "never rests a trigger without a cooldown", %{table: table, trigger: trigger} do
      trigger = %{trigger | cooldown_ms: 0}

      assert AreaTriggerCooldown.claim(WorldRef.open(0), trigger, 0, table)
      assert AreaTriggerCooldown.claim(WorldRef.open(0), trigger, 0, table)
    end
  end
end
