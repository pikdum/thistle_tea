defmodule ThistleTea.Game.Entity.Logic.MovementStatsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Spell

  defp entity(auras \\ []) do
    %{
      movement_block: Map.merge(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds()),
      unit: %Unit{auras: auras}
    }
  end

  defp snare(amount) do
    [
      %Holder{
        spell: %Spell{id: 1, name: "Snare"},
        slot: 0,
        caster_guid: 1,
        auras: [%Aura{type: :mod_decrease_speed, amount: amount}]
      }
    ]
  end

  describe "recompute/1" do
    test "derives speeds from base values" do
      recomputed = MovementStats.recompute(entity())

      assert recomputed.movement_block.run_speed == 7.0
      assert recomputed.movement_block.swim_speed == 4.722222
    end

    test "is idempotent with auras applied" do
      once = MovementStats.recompute(entity(snare(-30)))
      twice = MovementStats.recompute(once)

      assert_in_delta once.movement_block.run_speed, 4.9, 0.000001
      assert twice.movement_block == once.movement_block
    end
  end

  describe "set_run_speed_rate/2" do
    test "scales base run speed" do
      changed = MovementStats.set_run_speed_rate(entity(), 5.0)

      assert changed.movement_block.base_run_speed == 35.0
      assert changed.movement_block.run_speed == 35.0
    end

    test "survives aura recomputes and layers snares on top" do
      changed = MovementStats.set_run_speed_rate(entity(), 5.0)

      snared = MovementStats.recompute(%{changed | unit: %Unit{auras: snare(-50)}})
      assert snared.movement_block.run_speed == 17.5

      restored = MovementStats.recompute(%{snared | unit: %Unit{auras: []}})
      assert restored.movement_block.run_speed == 35.0
    end
  end
end
