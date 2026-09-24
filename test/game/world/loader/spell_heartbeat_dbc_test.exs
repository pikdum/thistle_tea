defmodule ThistleTea.Game.World.Loader.SpellHeartbeatDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.Aura.Heartbeat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1 and build_spellbook/1" do
    test "retain heartbeat flags and engineering exceptions" do
      ids = [118, 605, 710, 1098, 2637, 6215, 6770, 13_181, 13_327, 133]
      spellbook = SpellLoader.build_spellbook(ids)

      for id <- ids do
        spell = SpellLoader.load(id)
        assert spellbook[id].attributes == spell.attributes
        assert Heartbeat.spell?(spell) == (id != 133)
        assert Spell.attribute?(spell, :heartbeat_resist) == id not in [13_181, 13_327, 133]
      end
    end
  end
end
