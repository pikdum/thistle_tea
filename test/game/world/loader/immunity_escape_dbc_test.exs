defmodule ThistleTea.Game.World.Loader.ImmunityEscapeDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Spell.CasterState
  alias ThistleTea.Game.Spell.Immunity
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "distinguishes targeted protection, triggered intervention, and self immunity" do
      for id <- [1022, 5599, 10_278, 19_752, 19_753] do
        assert Immunity.targeted_school_protection?(SpellLoader.load(id))
      end

      assert SpellLoader.load(19_752).triggers_school_immunity?

      for id <- [642, 1020, 11_958, 1953] do
        refute Immunity.targeted_school_protection?(SpellLoader.load(id))
      end
    end

    test "Divine Shield and Ice Block escape stuns and magic controls while Protection remains physical" do
      stun = holder(853)
      fear = holder(5782)
      silence = holder(15_487)
      caster = caster([stun, fear, silence])

      for id <- [642, 1020, 11_958] do
        assert CasterState.validate(caster, SpellLoader.load(id), 0) == :ok
      end

      protection = SpellLoader.load(1022)
      physical_stun = holder(408)
      assert CasterState.validate(caster([physical_stun]), protection, 0) == :ok
      assert CasterState.validate(caster([physical_stun, fear]), protection, 0) == {:error, :fleeing}
      assert CasterState.validate(caster([stun]), protection, 0) == {:error, :stunned}
    end

    test "Blink escapes stun with silence but remains blocked by silence alone" do
      blink = SpellLoader.load(1953)
      assert CasterState.validate(caster([holder(853), holder(15_487)]), blink, 0) == :ok
      assert CasterState.validate(caster([holder(15_487)]), blink, 0) == {:error, :silenced}
    end
  end

  defp caster(holders), do: %Character{unit: %Unit{auras: holders}, internal: %Internal{}}

  defp holder(id) do
    spell = SpellLoader.load(id)
    auras = for effect <- spell.effects, effect.aura != nil, do: %Aura{index: effect.index, type: effect.aura}
    %Holder{spell: spell, auras: auras, negative?: true}
  end
end
