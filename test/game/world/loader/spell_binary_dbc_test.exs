defmodule ThistleTea.Game.World.Loader.SpellBinaryDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "load/1" do
    test "classifies Frostbolt, Frost Nova, Earth Shock, Counterspell, and Mind Flay" do
      for id <- [116, 122, 8_042, 2_139, 15_407, 26_143, 26_478] do
        spell = SpellLoader.load(id)
        assert Spell.binary?(spell), "expected #{spell.name} (#{id}) to be binary"
        assert spell.semantics.binary?
      end
    end

    test "keeps Fireball, Shadow Bolt, Corruption, and Arcane Missiles nonbinary" do
      for id <- [133, 686, 172, 5_143] do
        spell = SpellLoader.load(id)
        refute Spell.binary?(spell), "expected #{spell.name} (#{id}) to be nonbinary"
      end
    end
  end

  describe "resolve/2" do
    test "triggered binary spells use current resistance and caster penetration" do
      caster_guid = Guid.from_low_guid(:mob, 1, 955_401)
      target_guid = Guid.from_low_guid(:player, 955_402)
      Metadata.put(target_guid, %{level: 60, school_resistances: %{4 => 300}})
      on_exit(fn -> Metadata.delete(target_guid) end)

      caster = %Mob{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, health: 1_000, max_health: 1_000},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}}
      }

      effect = Effects.trigger_spell(caster_guid, 60, target_guid, 116)
      :rand.seed(:exsss, {1, 1, 66})
      missed = Spells.resolve(caster, effect)
      assert Enum.any?(missed, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :resist}}, &1))

      caster = %{caster | unit: %{caster.unit | equipment_bonuses: %{resistance_penetration: [{16, -300}]}}}
      :rand.seed(:exsss, {1, 1, 66})
      hit = Spells.resolve(caster, effect)
      assert Enum.any?(hit, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :hit}}, &1))

      self_effect = Effects.trigger_spell(caster_guid, 60, caster_guid, 116)
      assert Spells.resolve(caster, self_effect) == []
    end
  end
end
