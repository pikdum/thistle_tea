defmodule ThistleTea.Game.Spell.StealthTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Stealth

  describe "validate/3" do
    test "requires an active stealth aura for players and creatures" do
      spell = %Spell{attributes: MapSet.new([:only_stealthed])}

      for caster <- [%Character{internal: %Internal{godmode: true}}, %Mob{}] do
        invisible = %{caster | unit: %Unit{auras: [holder(1, :mod_invisibility)]}}
        assert Stealth.validate(invisible, spell) == {:error, :only_stealthed}
        hidden = %{caster | unit: %Unit{auras: [holder(1784, :mod_stealth)]}}
        assert Stealth.validate(hidden, spell) == :ok
        assert Stealth.validate(invisible, spell, triggered?: true) == :ok
        assert Stealth.validate(invisible, %Spell{}) == :ok
      end
    end
  end

  describe "preserve?/3" do
    test "Improved Sap has exactly thirty, sixty and ninety successful percentile rolls" do
      for {id, chance} <- [{14_076, 30}, {14_094, 60}, {14_095, 90}] do
        caster = %Character{unit: %Unit{auras: [holder(id, :proc_trigger_spell)]}}
        sap = %Spell{spell_icon: 249}
        assert Stealth.preservation_chance(caster, sap) == chance
        assert Enum.count(1..100, &Stealth.preserve?(caster, sap, &1)) == chance
        refute Stealth.preserve?(caster, sap, nil)
        refute Stealth.preserve?(caster, sap, 0)
        refute Stealth.preserve?(caster, %Spell{spell_icon: 244}, 1)
        refute Stealth.preserve?(%Mob{unit: caster.unit}, sap, 1)
      end
    end

    test "the strongest active rank applies without adding chances" do
      caster = %Character{unit: %Unit{auras: Enum.map([14_076, 14_094, 14_095], &holder(&1, :proc_trigger_spell))}}
      assert Stealth.preservation_chance(caster, %Spell{spell_icon: 249}) == 90
      assert Stealth.preservation_chance(%Character{}, %Spell{spell_icon: 249}) == 0
    end

    test "stealth, Prowl, Vanish and allowed spells need no roll" do
      for spell <- [
            %Spell{spell_icon: 250},
            %Spell{spell_icon: 103},
            %Spell{spell_icon: 252},
            %Spell{attributes: MapSet.new([:allow_while_stealthed])}
          ] do
        assert Stealth.preserve?(%Character{}, spell, nil)
      end
    end
  end

  defp holder(id, type), do: %Holder{spell: %Spell{id: id}, auras: [%Aura{type: type}]}
end
