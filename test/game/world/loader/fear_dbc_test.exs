defmodule ThistleTea.Game.World.Loader.FearDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "replacing Curse of Recklessness restores an existing Fear" do
      fear = SpellLoader.load(6213)
      recklessness = SpellLoader.load(704)
      weakness = SpellLoader.load(702)
      entity = %Mob{unit: %Unit{health: 100, auras: []}}

      {entity, _events} = Aura.apply_spell(entity, 2, 50, fear, 0)
      assert Fear.active?(entity)
      {entity, _events} = Aura.apply_spell(entity, 2, 50, recklessness, 1_000)
      assert Aura.has_spell?(entity, fear.id)
      refute Fear.active?(entity)
      assert entity.internal.blackboard.fear == nil

      {entity, _events} = Aura.apply_spell(entity, 2, 50, weakness, 2_000)
      refute Aura.has_spell?(entity, recklessness.id)
      assert Fear.active?(entity)
      assert entity.internal.blackboard.fear != nil
    end

    test "Fear and Psychic Scream activate fleeing and expire normally" do
      for {id, name} <- [{5782, "Fear"}, {8122, "Psychic Scream"}, {1513, "Scare Beast"}] do
        spell = SpellLoader.load(id)
        assert spell.name == name
        entity = %Mob{unit: %Unit{health: 100, auras: []}}
        {active, _events} = Aura.apply_spell(entity, 2, 50, spell, 1_000)
        assert Fear.active?(active)
        assert Fear.source_guid(active) == 2
        assert active.internal.blackboard.fear != nil
        assert Bitwise.band(active.unit.flags, 0x00800000) != 0

        {expired, _events} = Aura.expire_due(active, 1_000 + spell.duration_ms)
        refute Fear.active?(expired)
        assert expired.internal.blackboard.fear == nil
        assert Bitwise.band(expired.unit.flags, 0x00800000) == 0
      end
    end
  end
end
