defmodule ThistleTea.Game.World.Loader.KnockbackDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db

  setup do
    for id <- [10_689, 11_019, 13_009, 16_716, 28_266, 28_337, 28_434, 28_618, 28_619, 28_620, 28_621] do
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
    test "loads every vanilla player pull as movement with a horizontal speed" do
      for {id, speed} <- [
            {28_266, 300},
            {28_337, 300},
            {28_434, 400},
            {28_618, 200},
            {28_619, 300},
            {28_620, 400},
            {28_621, 500}
          ] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.index == 0))
        assert %Effect{type: :player_pull, semantic: %Semantics.Movement{kind: :player_pull}} = effect
        assert effect.misc_value == speed
      end
    end

    test "loads real knockback effects and their independent speeds" do
      for {id, index, horizontal, vertical} <- [
            {10_689, 0, 100, 100..100},
            {11_019, 0, 120, 70..90},
            {13_009, 0, 300, 48..52},
            {16_716, 0, 0, 500..500}
          ] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.index == index))
        assert %Effect{type: :knockback, semantic: %Semantics.Movement{kind: :knockback}} = effect
        assert effect.misc_value == horizontal
        assert Effect.roll(effect, 0) in vertical
      end
    end
  end
end
