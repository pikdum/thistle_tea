defmodule ThistleTea.Game.World.Loader.SpellDispelResistanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.DispelResistance
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:modifier_mask_fixture]

  describe "load/1" do
    test "Vile Poisons protects poisons but not Garrote" do
      talent = SpellLoader.load(16_720)
      assert Enum.map(talent.effects, & &1.class_mask) == [73_728, 65_536, 268_550_144]
      entity = %{object: %Object{guid: 1}, unit: %Unit{level: 50, auras: []}}
      context = %CastContext{caster_guid: 1, caster_level: 50}
      {entity, _events} = Aura.apply_spell(entity, context, talent, 1_000)
      projection = DispelResistance.projection(entity)

      for id <- [2818, 3409, 13_218] do
        assert DispelResistance.chance(projection, SpellLoader.load(id)) == 40, "poison spell #{id}"
      end

      assert DispelResistance.chance(projection, SpellLoader.load(703)) == 0
    end
  end

  defp modifier_mask_fixture(_context) do
    key = {:class_masks, 16_720}
    previous = :ets.lookup(SpellEffectOverride, key)
    :ets.insert(SpellEffectOverride, {key, {73_728, 65_536, 268_550_144}})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
