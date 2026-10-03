defmodule ThistleTea.Game.Core.AI.CreatureScript.MagramiSpectreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @spectre 11_560

  describe "events/1" do
    test "drifts in blue, turns green and hostile at the magnet, and curses its foe" do
      [spawned, arrived, home, curse] = CreatureScript.events(@spectre)

      assert [[%ScriptStep{command: :add_aura, datalong: 17_327}]] = spawned.actions
      assert %{event_type: :movement_inform, param1: 9, param2: 2} = arrived
      assert %{event_type: :reached_home} = home

      assert [
               %ScriptStep{command: :remove_aura, datalong: 17_327},
               %ScriptStep{command: :add_aura, datalong: 18_951},
               %ScriptStep{command: :set_faction, datalong: 16}
             ] = hd(arrived.actions)

      assert arrived.actions == home.actions

      assert %{event_type: :timer_in_combat, param1: 5_000, param2: 9_000, param3: 15_000, param4: 21_000} = curse

      assert [[%ScriptStep{command: :cast_spell, datalong: 18_159, datalong2: 0x20, target_type: :victim}]] =
               curse.actions
    end
  end
end
