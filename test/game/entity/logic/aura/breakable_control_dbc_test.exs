defmodule ThistleTea.Game.Entity.Logic.Aura.BreakableControlDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "breakable_crowd_control?/1" do
    test "protects Polymorph, Gouge, Freezing Trap, Sap, and Repentance" do
      for id <- [118, 1776, 3355, 6770, 20_066] do
        assert Aura.breakable_crowd_control?(controlled(id)), "spell #{id}"
      end
    end

    test "permits attacks through Frost Nova, Hammer of Justice, and Fear" do
      for id <- [122, 853, 5782] do
        refute Aura.breakable_crowd_control?(controlled(id)), "spell #{id}"
      end
    end
  end

  defp controlled(id) do
    spell = SpellLoader.load(id)
    auras = Enum.map(spell.effects, &%ThistleTea.Game.Aura{type: &1.aura})
    %Mob{unit: %Unit{auras: [%Holder{spell: spell, auras: auras}]}}
  end
end
