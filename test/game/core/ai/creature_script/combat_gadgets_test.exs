defmodule ThistleTea.Game.Core.AI.CreatureScript.CombatGadgetsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @battle_chicken 8_836
  @arcanite_dragonling 12_473
  @emerald_dragon_whelp 8_776
  @felhound_minions [9_556, 10_656]

  describe "CreatureScript" do
    test "ports every combat gadget" do
      for entry <- [@battle_chicken, @arcanite_dragonling, @emerald_dragon_whelp | @felhound_minions] do
        assert CreatureScript.ported?(entry)
      end
    end
  end

  describe "events/1" do
    test "the battle chicken squawks once and flies into a fury through the fight" do
      [squawk, fury, refury] = CreatureScript.events(@battle_chicken)

      assert %{event_type: :timer_in_combat, param1: 30_000, param2: 80_000, repeatable?: false} = squawk
      assert [[%ScriptStep{command: :cast_spell, datalong: 23_060, target_self?: true}]] = squawk.actions

      assert %{event_type: :aggro} = fury
      assert [[%ScriptStep{command: :cast_spell, datalong: 13_168, target_self?: true}]] = fury.actions

      assert %{event_type: :timer_in_combat, param3: 25_000, param4: 25_000} = refury
      assert refury.actions == fury.actions
    end

    test "the arcanite dragonling buffets and breathes fire on its victim" do
      [buffet, breath] = CreatureScript.events(@arcanite_dragonling)

      assert %{param1: 5_000, param2: 5_000, param3: 22_500, param4: 22_500} = buffet
      assert [[%ScriptStep{command: :cast_spell, datalong: 9_658, target_type: :victim}]] = buffet.actions

      assert %{param1: 10_000, param2: 60_000, param3: 10_000, param4: 60_000} = breath
      assert [[%ScriptStep{command: :cast_spell, datalong: 8_873, target_type: :victim}]] = breath.actions
    end

    test "the emerald whelp spits acid every two seconds" do
      [spit] = CreatureScript.events(@emerald_dragon_whelp)

      assert %{event_type: :timer_in_combat, param1: 1_000, param3: 2_000, param4: 2_000} = spit
      assert [[%ScriptStep{command: :cast_spell, datalong: 9_591, target_type: :victim}]] = spit.actions
    end

    test "felhounds burn their victim's mana" do
      for entry <- @felhound_minions do
        [burn] = CreatureScript.events(entry)

        assert %{event_type: :timer_in_combat, param3: 9_800, param4: 15_200} = burn
        assert [[%ScriptStep{command: :cast_spell, datalong: 15_980, target_type: :victim}]] = burn.actions
      end
    end
  end
end
