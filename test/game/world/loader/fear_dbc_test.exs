defmodule ThistleTea.Game.World.Loader.FearDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
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
