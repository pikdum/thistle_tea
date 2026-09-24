defmodule ThistleTea.Game.World.Loader.SpellShapeshiftDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Shapeshift
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db
  @spell_ids [116, 122, 339, 546, 768, 1604, 1715, 5116, 9033, 24_858]

  setup do
    previous = for id <- @spell_ids, do: {id, :ets.lookup(SpellChain, {:chain, id})}
    Enum.each(previous, fn {id, _} -> :ets.insert(SpellChain, {{:chain, id}, nil}) end)

    on_exit(fn ->
      for {id, entries} <- previous do
        :ets.delete(SpellChain, {:chain, id})
        :ets.insert(SpellChain, entries)
      end
    end)

    :ok
  end

  describe "load/1" do
    test "real roots and snares cleanse while melee daze stays" do
      for id <- [116, 122, 339, 1715, 5116] do
        assert Shapeshift.removable_spells([holder(SpellLoader.load(id))]) == [id]
      end

      assert Shapeshift.removable_spells([holder(SpellLoader.load(1604))]) == []
      assert Semantics.rules(SpellLoader.load(9033)).dummy == :shapeshift_cleanse
    end

    test "Cat cancels Water Walking while Moonkin retains it" do
      water_walk = holder(SpellLoader.load(546))
      cat = holder(SpellLoader.load(768))
      moonkin = holder(SpellLoader.load(24_858))
      assert Shapeshift.interrupt_holders([water_walk], [cat, water_walk]) == [cat]
      assert Shapeshift.interrupt_holders([water_walk], [moonkin, water_walk]) == [moonkin, water_walk]
      assert {:error, :bad_targets} = Shapeshift.validate_target(nil, water_walk.spell, %{shapeshift_form: 1})
      assert :ok = Shapeshift.validate_target(nil, water_walk.spell, %{shapeshift_form: 31})
    end
  end

  defp holder(%Spell{} = spell) do
    %Holder{
      spell: spell,
      caster_guid: 7,
      auras: for(effect <- Spell.aura_effects(spell), do: %Aura{type: effect.aura, misc_value: effect.misc_value})
    }
  end
end
