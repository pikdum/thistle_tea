defmodule ThistleTea.Game.Spell.SemanticsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics

  describe "compile/1" do
    test "classifies DBC effects by semantic family" do
      spell = %Spell{
        id: 1,
        effects: [
          %Effect{type: :school_damage},
          %Effect{type: :apply_aura},
          %Effect{type: :energize},
          %Effect{type: :leap},
          %Effect{type: :summon_pet},
          %Effect{type: :create_item},
          %Effect{type: :dummy}
        ]
      }

      assert [
               %Semantics.DamageHeal{kind: :school_damage},
               %Semantics.Aura{kind: :apply_aura},
               %Semantics.Resource{kind: :energize},
               %Semantics.Movement{kind: :leap},
               %Semantics.SummonControl{kind: :summon_pet},
               %Semantics.Inventory{kind: :create_item},
               %Semantics.Script{kind: :dummy}
             ] = Enum.map(Semantics.compile(spell).effects, & &1.semantic)
    end

    test "compiles VMangos script names into typed spell rules" do
      spell = %Spell{id: 1, script_name: "spell_warrior_execute_dummy"}

      assert %Semantics.Rules{dummy: :execute} = Semantics.compile(spell).semantics
    end
  end
end
