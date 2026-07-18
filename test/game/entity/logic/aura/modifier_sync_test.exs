defmodule ThistleTea.Game.Entity.Logic.Aura.ModifierSyncTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.ModifierSync
  alias ThistleTea.Game.Entity.Logic.Event

  describe "events/2" do
    test "emits absolute totals for changed mask bits" do
      first = holder(:add_flat_modifier, -100, 10, 0b101)
      second = holder(:add_flat_modifier, -200, 10, 0b001)

      assert ModifierSync.events([], [first, second]) == [
               %Event{type: :spell_modifier, modifier_type: :flat, effect_index: 0, operation: 10, amount: -300},
               %Event{type: :spell_modifier, modifier_type: :flat, effect_index: 2, operation: 10, amount: -100}
             ]
    end

    test "emits zero when a modifier disappears" do
      modifier = holder(:add_pct_modifier, -100, 10, 1 <<< 30)

      assert ModifierSync.events([modifier], []) == [
               %Event{type: :spell_modifier, modifier_type: :pct, effect_index: 30, operation: 10, amount: 0}
             ]
    end

    test "accounts for holder stacks" do
      modifier = %{holder(:add_flat_modifier, -100, 10, 1) | stacks: 3}

      assert ModifierSync.totals([modifier]) == %{{:flat, 0, 10} => -300}
    end
  end

  defp holder(type, amount, operation, mask) do
    %Holder{auras: [%Aura{type: type, amount: amount, misc_value: operation, class_mask: mask}]}
  end
end
