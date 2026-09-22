defmodule ThistleTea.Game.World.Loader.TaxiSpellDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db
  @routes [{27_998, 315}, {28_001, 316}, {28_129, 472}, {29_931, 494}, {29_934, 495}, {29_994, 496}]

  setup do
    for {id, _path} <- @routes do
      key = {:chain, id}
      previous = :ets.lookup(SpellChain, key)
      :ets.insert(SpellChain, {key, %{first_spell: id, rank: 1}})

      on_exit(fn ->
        :ets.delete(SpellChain, key)
        :ets.insert(SpellChain, previous)
      end)
    end

    :ok
  end

  describe "load/1" do
    test "loads all vanilla taxi spells with their route ids" do
      for {id, path} <- @routes do
        spell = SpellLoader.load(id)

        assert [%Effect{type: :send_taxi, misc_value: ^path, semantic: %Semantics.Movement{kind: :send_taxi}}] =
                 spell.effects
      end
    end
  end
end
