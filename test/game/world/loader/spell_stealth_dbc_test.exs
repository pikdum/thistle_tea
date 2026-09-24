defmodule ThistleTea.Game.World.Loader.SpellStealthDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Stealth
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db
  @openers [703, 921, 1833, 6770, 2070, 11_297, 8676, 11_269, 6785, 9867, 9005, 9827]
  @other [1784, 5215, 1856, 1725, 14_076, 14_094, 14_095, 14_183]

  setup do
    previous = for id <- @openers ++ @other, do: {id, :ets.lookup(SpellChain, {:chain, id})}
    Enum.each(previous, fn {id, _} -> :ets.insert(SpellChain, {{:chain, id}, nil}) end)

    on_exit(fn ->
      for {id, entries} <- previous do
        :ets.delete(SpellChain, {:chain, id})
        :ets.insert(SpellChain, entries)
      end
    end)

    :ok
  end

  describe "load/1 and build_spellbook/1" do
    test "preserve stealth requirements and the full Improved Sap rank chances" do
      book = SpellLoader.build_spellbook(@openers ++ @other)

      for id <- @openers ++ @other do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :only_stealthed) == id in @openers, "stealth prerequisite for #{id}"
        assert book[id].attributes == spell.attributes
      end

      for {id, chance} <- [{14_076, 30}, {14_094, 60}, {14_095, 90}] do
        caster = %Character{unit: %Unit{auras: [%Holder{spell: book[id]}]}}

        for sap_id <- [6770, 2070, 11_297] do
          assert Stealth.preservation_chance(caster, book[sap_id]) == chance
          refute Spell.starts_combat?(book[sap_id])
          assert Spell.attribute?(book[sap_id], :only_peaceful_targets)
        end
      end

      for id <- [1784, 5215, 1856, 1725, 921, 14_183], do: assert(Stealth.exempt?(book[id]))
    end
  end
end
