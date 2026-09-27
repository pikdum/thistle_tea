defmodule ThistleTea.Game.World.Loader.MechanicalHealingDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Semantics.DamageHeal
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Mechanical Patch Kit restores its real DBC amount" do
      spell = SpellLoader.load(15_057)
      assert [%{type: :heal_mechanical, semantic: %DamageHeal{}, implicit_target_a: :target_ally}] = spell.effects
      assert spell.target_creature_type_mask == 256
      assert Spell.healing?(spell)

      target = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 1_000, level: 60, auras: []},
        internal: %Internal{}
      }

      context = %CastContext{caster_guid: 2, caster_level: 60, spell_crit_chance: 100}

      {target, [%Effects.SpellHeal{damage: 700, crit?: false, proc_type: nil}]} =
        SpellEffect.receive(target, context, spell, 0)

      assert target.unit.health == 800
    end
  end
end
