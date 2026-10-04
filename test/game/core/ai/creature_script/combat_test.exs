defmodule ThistleTea.Game.Core.AI.CreatureScript.CombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @entry 1_000

  describe "every/6" do
    test "rolls its first and repeat delays from ranges" do
      event = Combat.every(@entry, 1, Combat.cast(133), {2_000, 3_000}, 8_000)

      assert %{id: 100_001, event_type: :timer_in_combat, repeatable?: true} = event
      assert %{param1: 2_000, param2: 3_000, param3: 8_000, param4: 8_000} = event
    end

    test "tries a failed cast again instead of waiting out its repeat" do
      event = Combat.every(@entry, 1, [Combat.cast(133), Combat.talk(1)], 0, 8_000)

      assert event.check_result?

      assert [[%ScriptStep{command: :cast_spell, abort_on_failure?: true}, %ScriptStep{command: :talk} = talk]] =
               event.actions

      refute talk.abort_on_failure?
    end

    test "leaves conditional casts and opted-out timers alone" do
      conditional = %{Combat.cast(133) | condition: %Condition{type: :alive}}
      assert [[%ScriptStep{abort_on_failure?: false}]] = Combat.every(@entry, 1, conditional, 0, 8_000).actions

      unchecked = Combat.every(@entry, 2, Combat.cast(133), 0, 8_000, check_result?: false)
      refute unchecked.check_result?
    end
  end

  describe "below_health/6" do
    test "fires once or keeps repeating under its threshold" do
      once = Combat.below_health(@entry, 1, Combat.cast(133, :self), 30)
      assert %{event_type: :hp, param1: 30, repeatable?: false, check_result?: true} = once
      assert [[%ScriptStep{target_self?: true, abort_on_failure?: true}]] = once.actions

      repeating = Combat.below_health(@entry, 2, Combat.cast(133), 50, {10_000, 12_000}, condition: %Condition{})
      assert %{param1: 50, param3: 10_000, param4: 12_000, repeatable?: true, condition: %Condition{}} = repeating
    end
  end
end
