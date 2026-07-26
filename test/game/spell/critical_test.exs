defmodule ThistleTea.Game.Spell.CriticalTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Critical
  alias ThistleTea.Game.Spell.Critical.Modifier

  describe "snapshot/2" do
    test "translates every Shatter rank into a frozen-target crit modifier" do
      caster =
        entity([
          override_holder(849),
          override_holder(910),
          override_holder(911),
          override_holder(912),
          override_holder(913)
        ])

      assert Enum.map(Critical.snapshot(caster, %Spell{spell_family: 3}), & &1.amount) == [10, 20, 30, 40, 50]
    end

    test "ignores override scripts from another spell family" do
      caster = entity([override_holder(913, spell_family: 3)])

      assert Critical.snapshot(caster, %Spell{spell_family: 5}) == []
    end

    test "ignores unrelated override class scripts" do
      caster = entity([override_holder(833)])

      assert Critical.snapshot(caster, %Spell{spell_family: 3}) == []
    end

    test "feeds applicable modifiers into the cast-time snapshot" do
      caster = entity([override_holder(913)])
      context = CastContext.from_caster(caster, %Spell{spell_family: 3}, 2)

      assert context.conditional_crit_modifiers == [
               %Modifier{condition: :target_frozen, amount: 50}
             ]
    end
  end

  describe "target_bonus/2" do
    test "applies frozen-target modifiers to Frost roots and stuns" do
      modifiers = [%Modifier{condition: :target_frozen, amount: 50}]

      assert Critical.target_bonus(modifiers, entity([control_holder(:frost, :mod_root)])) == 50
      assert Critical.target_bonus(modifiers, entity([control_holder(:frost, :mod_stun)])) == 50
    end

    test "does not treat non-Frost control or Frost slows as frozen" do
      modifiers = [%Modifier{condition: :target_frozen, amount: 50}]

      assert Critical.target_bonus(modifiers, entity([control_holder(:nature, :mod_root)])) == 0
      assert Critical.target_bonus(modifiers, entity([control_holder(:holy, :mod_stun)])) == 0
      assert Critical.target_bonus(modifiers, entity([control_holder(:frost, :mod_decrease_speed)])) == 0
    end
  end

  describe "frozen?/1" do
    test "derives frozen state from active Frost control holders" do
      assert AuraLogic.frozen?(entity([control_holder(:frost, :mod_root)]))
      refute AuraLogic.frozen?(entity([control_holder(:nature, :mod_root)]))
    end
  end

  defp entity(holders), do: %{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: holders}}

  defp override_holder(script, opts \\ []) do
    %Holder{
      spell: %Spell{spell_family: Keyword.get(opts, :spell_family, 3)},
      auras: [%Aura{type: :override_class_scripts, misc_value: script}]
    }
  end

  defp control_holder(school, type) do
    %Holder{
      spell: %Spell{school: school},
      auras: [%Aura{type: type}]
    }
  end
end
