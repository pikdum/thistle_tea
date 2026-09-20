defmodule ThistleTea.Game.Entity.Logic.SpellMagnetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Totem, as: TotemBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  describe "aura lifecycle" do
    test "application, removal, expiry and death publish magnet transitions" do
      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 10, auras: []},
        internal: %Internal{}
      }

      spell = %Spell{
        id: 8178,
        duration_ms: 1000,
        proc_charges: 1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :spell_magnet}]
      }

      {protected, events} = Aura.apply_spell(mob, 1, 10, spell, 100)
      assert [%Effects.SpellMagnetsChanged{magnets: [magnet]}] = magnet_events(events)
      assert magnet.source_guid == 1
      assert magnet.charges == 1
      assert magnet.expires_at == 1100

      for {result, events} <- [Aura.remove_spells(protected, [8178], 200), Aura.expire_due(protected, 1100)] do
        assert result.unit.auras == []
        assert [%Effects.SpellMagnetsChanged{magnets: []}] = magnet_events(events)
      end

      dead = Core.take_damage(protected, 100, 200)
      assert [%Effects.SpellMagnetsChanged{magnets: []}] = magnet_events(dead.internal.events)
    end
  end

  describe "cast/3" do
    test "a spent passive totem does not recreate its aura" do
      totem = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, auras: []},
        internal: %Internal{totem: %Totem{owner_guid: 2, passive_spell_started?: true}}
      }

      blackboard = Blackboard.new()
      assert {:failure, ^totem, ^blackboard} = TotemBT.cast(totem, blackboard, Context.new(2000))
    end
  end

  describe "receive/4" do
    test "totems reject redirected debuffs while still receiving direct damage" do
      totem = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 50, auras: []},
        internal: %Internal{totem: %Totem{owner_guid: 2}}
      }

      context = %CastContext{caster_guid: 3, caster_level: 50, target_guid: 1, target_hostile?: true}

      debuff = %Spell{
        id: 116,
        school: :physical,
        dmg_class: 1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_decrease_speed, implicit_target_a: :target_enemy}]
      }

      {unchanged, events} = SpellEffect.receive(totem, context, debuff, 100)
      assert unchanged.unit.auras == []
      assert [%Effects.SpellLogMiss{reason: :immune}] = events

      mixed = %{debuff | effects: [%Effect{index: 1, type: :school_damage, base_points: 20} | debuff.effects]}
      {damaged, events} = SpellEffect.receive(totem, context, mixed, 100)
      assert damaged.unit.health == 80
      assert damaged.unit.auras == []
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 20}, &1))
    end

    test "totem regeneration immunity preserves self casts and Shaman totem healing" do
      totem = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 50, max_health: 100, level: 50, auras: []},
        internal: %Internal{totem: %Totem{owner_guid: 2}}
      }

      context = %CastContext{caster_guid: 2, caster_level: 50, target_guid: 1}
      heal = %Spell{id: 10, effects: [%Effect{index: 0, type: :heal, base_points: 20}]}
      {unchanged, [%Effects.SpellLogMiss{reason: :immune}]} = SpellEffect.receive(totem, context, heal, 100)
      assert unchanged.unit.health == 50
      {self_healed, _} = SpellEffect.receive(totem, %{context | caster_guid: 1}, heal, 100)
      assert self_healed.unit.health == 70
      {healed, _} = SpellEffect.receive(totem, context, %{heal | spell_family: 11, family_flags_0: 0x2000}, 100)
      assert healed.unit.health == 70
    end
  end

  defp magnet_events(events), do: Enum.filter(events, &match?(%Effects.SpellMagnetsChanged{}, &1))
end
