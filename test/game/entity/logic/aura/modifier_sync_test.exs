defmodule ThistleTea.Game.Entity.Logic.Aura.ModifierSyncTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.ModifierSync
  alias ThistleTea.Game.Entity.Logic.Effects

  describe "restore/1" do
    test "resends retained aura totals after pending login changes" do
      modifier = holder(:add_flat_modifier, -5_000, 11, 1)
      stale = Effects.spell_modifier(:flat, 0, 11, -1_000)
      character = %Character{unit: %Unit{auras: [modifier]}, internal: %Internal{}}
      character = character |> Effects.enqueue(stale) |> ModifierSync.restore()
      {restored, events} = Effects.drain(character)

      assert events == [stale, Effects.spell_modifier(:flat, 0, 11, -5_000)]
      assert restored.unit.auras == [modifier]
    end
  end

  describe "events/2" do
    test "emits absolute totals for changed mask bits" do
      first = holder(:add_flat_modifier, -100, 10, 0b101)
      second = holder(:add_flat_modifier, -200, 10, 0b001)

      assert ModifierSync.events([], [first, second]) == [
               %Effects.SpellModifier{modifier_type: :flat, effect_index: 0, operation: 10, amount: -300},
               %Effects.SpellModifier{modifier_type: :flat, effect_index: 2, operation: 10, amount: -100}
             ]
    end

    test "emits zero when a modifier disappears" do
      modifier = holder(:add_pct_modifier, -100, 10, 1 <<< 30)

      assert ModifierSync.events([modifier], []) == [
               %Effects.SpellModifier{modifier_type: :pct, effect_index: 30, operation: 10, amount: 0}
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
