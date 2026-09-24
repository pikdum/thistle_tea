defmodule ThistleTea.Game.OutdoorPvp.PlaguelandsRewardsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template
  alias ThistleTea.Game.OutdoorPvp.PlaguelandsRewards
  alias ThistleTea.Game.OutdoorPvp.Towers

  describe "spawns/1" do
    test "grants services at capture, flares at full control, and clears them at neutrality" do
      assert PlaguelandsRewards.spawns(%Towers{}) == %{}
      controlled = towers({:progress, :alliance})
      spawns = PlaguelandsRewards.spawns(controlled)
      assert map_size(spawns) == 10
      assert spawns[{:northpass, :shrine}].entry == 181_682
      assert spawns[{:plaguewood, :flightmaster}].faction == 774
      assert spawns[{:eastwall, 0}].entry == 17_635
      assert spawns[{:eastwall, 4}].entry == 17_647
      assert PlaguelandsRewards.graveyard_owner(controlled) == :alliance
      full = PlaguelandsRewards.spawns(towers({:controlled, :alliance}))
      assert map_size(full) == 14
      assert Map.take(full, Map.keys(spawns)) == spawns
      assert full[{:northpass, :flare}].entry == 181_852
      assert PlaguelandsRewards.spawns(towers({:contested, :horde})) == %{}
      assert PlaguelandsRewards.graveyard_owner(towers({:contested, :horde})) == nil
    end

    test "switches faction-specific services and reinforcements together" do
      spawns = PlaguelandsRewards.spawns(towers({:progress, :horde}))
      assert spawns[{:northpass, :shrine}].entry == 181_955
      assert spawns[{:plaguewood, :flightmaster}].faction == 775
      assert spawns[{:crown_guard, :aura}].entry == 180_422
      assert spawns[{:crown_guard, :spirit}].aura == 31_951
      assert spawns[{:eastwall, 0}].entry == 17_995
      assert spawns[{:eastwall, 4}].entry == 17_996
    end
  end

  defp towers(phase) do
    template = %Template{
      entry: 1,
      radius: 80,
      display_state: 2426,
      position_state: 2427,
      neutral_state: 2428,
      neutral_percent: 20,
      min_time: 480,
      max_time: 1200
    }

    %Towers{
      points:
        Map.new(
          [:northpass, :eastwall, :crown_guard, :plaguewood],
          &{&1, %CapturePoint{template: template, phase: phase}}
        )
    }
  end
end
