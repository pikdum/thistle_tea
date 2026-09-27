defmodule ThistleTea.Game.World.Loader.SharedDamageDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.SharedDamage
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName

  @moduletag :dbc_db
  @spell_ids [24_340, 26_558, 26_789, 28_884]

  setup do
    previous = Enum.flat_map(@spell_ids, &:ets.lookup(SpellScriptName, &1))
    Enum.each(@spell_ids, &:ets.insert(SpellScriptName, {&1, "spell_meteor"}))

    on_exit(fn ->
      Enum.each(@spell_ids, &:ets.delete(SpellScriptName, &1))
      :ets.insert(SpellScriptName, previous)
    end)

    :ok
  end

  describe "load/1" do
    test "Meteor variants and Shard of the Fallen Star divide only their damage effect" do
      for id <- @spell_ids do
        spell = SpellLoader.load(id)
        assert SharedDamage.required?(spell)
        assert spell.semantics.shared_damage_effects == [0]
        assert [%Effect{index: 0, type: :school_damage, area_target?: true} = effect] = spell.effects
        assert :aoe_enemy_at_dest in [effect.implicit_target_a, effect.implicit_target_b]
      end

      refute SharedDamage.required?(SpellLoader.load(1449))
    end
  end
end
