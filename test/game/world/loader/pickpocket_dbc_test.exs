defmodule ThistleTea.Game.World.Loader.PickpocketDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Pickpocket
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Pick Pocket keeps stealth on success and provokes its target on failure" do
      spell = SpellLoader.load(921)
      assert Pickpocket.spell?(spell)
      assert Spell.attribute?(spell, :allow_while_stealthed)
      assert Spell.attribute?(spell, :failure_breaks_stealth)
      assert Spell.attribute?(spell, :threat_only_on_miss)
      assert Spell.harmful?(spell)
      refute Spell.starts_combat?(spell)
      assert Spell.starts_combat?(spell, :miss)
      assert spell.range_yards == 5.0

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, level: 50, auras: []},
        player: %Player{},
        internal: %Internal{}
      }

      {character, _} = Aura.apply_spell(character, 1, 50, SpellLoader.load(1786), 0)
      assert Aura.has_aura?(character, :mod_stealth)
      character = Casting.start(character, spell, Target.unit(2), 1_000)
      assert Aura.has_aura?(character, :mod_stealth)
    end
  end
end
