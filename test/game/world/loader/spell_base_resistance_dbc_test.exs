defmodule ThistleTea.Game.World.Loader.SpellBaseResistanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:raw_dbc_effects]

  describe "load/1" do
    test "loads flat base armor and magical resistance auras" do
      for {id, amount, mask} <- [{819, 15, 1}, {21_740, 100, 126}, {21_925, 40, 126}] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.aura == :mod_base_resistance))
        assert effect.misc_value == mask
        assert effect.base_points + 1 == amount

        target = %Mob{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: []}, internal: %Internal{}}
        {target, _events} = Aura.apply_spell(target, 1, 60, spell, 0)

        if mask == 1 do
          assert target.unit.normal_resistance == amount
          assert target.unit.fire_resistance == 0
        else
          assert target.unit.normal_resistance == 0
          assert target.unit.fire_resistance == amount
          assert target.unit.frost_resistance == amount
          assert target.unit.nature_resistance == amount
        end
      end
    end
  end

  defp raw_dbc_effects(_context) do
    ids = [819, 21_740, 21_925]
    previous = Enum.flat_map(ids, &:ets.take(SpellEffectOverride, {:mods, &1}))

    on_exit(fn ->
      Enum.each(ids, &:ets.delete(SpellEffectOverride, {:mods, &1}))
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
