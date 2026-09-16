defmodule ThistleTea.Game.Entity.Logic.MechanicResistanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.MechanicResistance
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "projection/1" do
    test "retains only mechanic resistance auras" do
      entity = %{
        unit: %Unit{
          auras: [
            %Holder{
              auras: [
                %Aura{type: :mechanic_resistance, misc_value: 12, amount: 25},
                %Aura{type: :mod_dodge, misc_value: 12, amount: 50}
              ]
            }
          ]
        }
      }

      assert MechanicResistance.projection(entity) == [{12, 25}]
    end
  end

  describe "chance/2" do
    test "sums matching mechanics using identifiers rather than bit masks" do
      assert MechanicResistance.chance([{12, 25}, {12, 15}, {4, 100}], 12) == 40
      assert MechanicResistance.chance([{0, 100}], 0) == 0
      assert MechanicResistance.chance(nil, 12) == 0
    end
  end

  describe "effect_resisted?/4" do
    test "uses an exclusive percentage boundary" do
      spell = %Spell{mechanic: 0}
      effect = %Effect{mechanic: 12}

      assert MechanicResistance.effect_resisted?([{12, 25}], spell, effect, 24)
      refute MechanicResistance.effect_resisted?([{12, 25}], spell, effect, 25)
      refute MechanicResistance.effect_resisted?([{7, 100}], spell, effect, 0)
    end

    test "does not reroll the whole spell mechanic or effects without a mechanic" do
      refute MechanicResistance.effect_resisted?([{12, 100}], %Spell{mechanic: 12}, %Effect{mechanic: 12}, 0)
      refute MechanicResistance.effect_resisted?([{0, 100}], %Spell{}, %Effect{}, 0)
    end
  end
end
