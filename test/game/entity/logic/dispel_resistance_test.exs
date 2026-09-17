defmodule ThistleTea.Game.Entity.Logic.DispelResistanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.DispelResistance
  alias ThistleTea.Game.Spell

  describe "projection/1" do
    test "includes only resistance modifiers and scales their stacks" do
      modifier = %Aura{type: :add_flat_modifier, misc_value: 28, class_mask: 2, amount: 15}

      entity = %{
        unit: %{
          auras: [
            %Holder{
              spell: %Spell{id: 1, spell_family: 7},
              stacks: 2,
              auras: [modifier, %{modifier | misc_value: 14}, %{modifier | type: :dummy}]
            }
          ]
        }
      }

      assert [{7, %{modifier | amount: 30}}] == DispelResistance.projection(entity)
      assert DispelResistance.projection(%{unit: %{auras: []}}) == []
    end
  end

  describe "chance/2" do
    test "matches the aura spell's family and mask" do
      projection = [{7, %Aura{type: :add_flat_modifier, misc_value: 28, class_mask: 2, amount: 30}}]
      spell = %Spell{id: 2, spell_family: 7, family_flags_0: 2}
      assert DispelResistance.chance(projection, spell) == 30
      assert DispelResistance.chance(projection, %{spell | spell_family: 3}) == 0
      assert DispelResistance.chance(projection, %{spell | family_flags_0: 4}) == 0
      assert DispelResistance.chance([], spell) == 0
    end

    test "combines flat and percent modifiers and bounds the result" do
      flat = %Aura{type: :add_flat_modifier, misc_value: 28, class_mask: 0, amount: 40}
      percent = %{flat | type: :add_pct_modifier, amount: 50}
      spell = %Spell{id: 2, spell_family: 7}
      assert DispelResistance.chance([{7, flat}, {7, percent}], spell) == 60
      assert DispelResistance.chance([{7, %{flat | amount: 200}}], spell) == 100
      assert DispelResistance.chance([{7, %{flat | amount: -10}}], spell) == 0
    end
  end
end
