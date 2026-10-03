defmodule ThistleTea.Game.Core.AI.CreatureScript.MurkdeepTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @murkdeep 10_323

  describe "events/1" do
    test "Murkdeep sunders and nets his target, and flees once when nearly beaten" do
      assert [sunder, net, flee] = CreatureScript.events(@murkdeep)

      assert %{event_type: :timer_in_combat, param3: 5_000, param4: 9_000, actions: [[sunder_cast]]} = sunder
      assert %ScriptStep{command: :cast_spell, datalong: 11_971, target_type: :victim} = sunder_cast

      assert %{event_type: :timer_in_combat, param3: 9_000, param4: 15_000, actions: [[net_cast]]} = net
      assert %ScriptStep{command: :cast_spell, datalong: 6_533, target_type: :victim} = net_cast

      assert %{event_type: :hp, param1: 15, repeatable?: false, actions: [[%ScriptStep{command: :flee}]]} = flee
    end
  end
end
