defmodule ThistleTea.Game.World.Loader.SpellPetMasterTargetDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.SpellTarget
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "pet Sacrifice and owner talent effects target the caster's master" do
      for spell_id <- [7812, 19_438, 23_784, 23_830, 23_831, 23_832, 24_592] do
        spell = SpellLoader.load(spell_id)

        assert hd(spell.effects).implicit_target_a == :caster_master
        assert SpellTarget.target_query(spell, Target.none()) == :caster_master
      end

      infernal_fire = SpellLoader.load(24_826)
      assert SpellTarget.target_query(infernal_fire, Target.unit(7)) == {:unit_and_master, 7}
    end

    test "Voidwalker Sacrifice shields its owner against damage" do
      spell = SpellLoader.load(7812)

      owner = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      context = %CastContext{caster_guid: 2, caster_level: 60, target_role: :other}
      {shielded, _events} = SpellEffect.receive(owner, context, spell, 1_000)

      assert Enum.any?(shielded.unit.auras, fn holder ->
               holder.spell.id == 7812 and
                 Enum.any?(holder.auras, &(&1.type == :school_absorb and &1.amount > 100))
             end)

      {protected, absorbed} = Entity.take_damage_with_absorb(shielded, 100, 1_001, school: :physical)
      assert absorbed == 100
      assert protected.unit.health == 100
    end
  end
end
