defmodule ThistleTea.Game.World.Loader.EffectImmunityDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain

  @moduletag :dbc_db
  @spell_ids [829, 1069, 26_602]

  setup do
    previous = Map.new(@spell_ids, &{&1, :ets.lookup(SpellChain, {:chain, &1})})
    Enum.each(@spell_ids, &:ets.insert(SpellChain, {{:chain, &1}, nil}))

    on_exit(fn ->
      Enum.each(previous, fn {id, rows} ->
        :ets.delete(SpellChain, {:chain, id})
        :ets.insert(SpellChain, rows)
      end)
    end)

    :ok
  end

  describe "load/1" do
    test "normalizes state and effect immunity targets" do
      assert [%Effect{aura: :state_immunity, misc_value: :mod_stun}] = SpellLoader.load(829).effects
      spell = SpellLoader.load(26_602)
      assert Enum.any?(spell.effects, &match?(%Effect{aura: :state_immunity, misc_value: :mod_taunt}, &1))
      assert Enum.any?(spell.effects, &match?(%Effect{aura: :effect_immunity, misc_value: :attack_me}, &1))
      assert Spell.attribute?(spell, :immunity_purges_effect)
    end

    test "loads purge and both-polarity flags for stealth immunity" do
      spell = SpellLoader.load(1069)
      assert Spell.attribute?(spell, :immunity_purges_effect)
      assert Spell.attribute?(spell, :immunity_to_hostile_and_friendly_effects)
      assert Enum.any?(spell.effects, &match?(%Effect{aura: :state_immunity, misc_value: :mod_stealth}, &1))
    end
  end
end
