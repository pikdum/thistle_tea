defmodule ThistleTea.Game.Entity.Logic.Aura.ControlSyncTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Aura.ControlSync
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  describe "sync/1" do
    test "control release interrupts prepared casts and clears their global cooldown" do
      for type <- [:mod_charm, :mod_possess, :mod_possess_pet] do
        original_pet = if type == :mod_possess_pet, do: %Pet{kind: :hunter, owner_guid: 7}

        mob = %Mob{
          object: %Object{guid: 20},
          unit: %Unit{auras: [holder(type)], faction_template: 14},
          internal: %Internal{pet: original_pet}
        }

        {controlled, _events} = ControlSync.sync(mob, 0)
        spell = %Spell{id: 11_829, cast_time_ms: 3_000, gcd_category: 133, gcd_ms: 1_500}
        cast = Cast.new(spell, Target.at({10.0, 0.0, 0.0}), 0)
        controlled = %{controlled | internal: %{controlled.internal | casting: cast}}
        controlled = Cooldowns.trigger_gcd(controlled, spell, 0)
        assert Cooldowns.on_gcd?(controlled, spell, 500)

        {released, _events} = ControlSync.sync(%{controlled | unit: %{controlled.unit | auras: []}}, 500)
        assert released.internal.casting == nil
        refute Cooldowns.on_gcd?(released, spell, 500)
        assert Enum.any?(released.internal.events, &match?(%Effects.SpellCastFailed{reason: :interrupted}, &1))
      end
    end

    test "control release tears down an active channel and its client projection" do
      mob = %Mob{
        object: %Object{guid: 20},
        unit: %Unit{auras: [holder(:mod_charm)], faction_template: 14}
      }

      {controlled, _events} = ControlSync.sync(mob, 0)
      spell = %Spell{id: 16_005, attributes: MapSet.new([:channeled]), duration_ms: 8_000}
      cast = %{Cast.new(spell, Target.at({10.0, 0.0, 0.0}), 0) | phase: :channel_tick}

      controlled = %{
        controlled
        | internal: %{controlled.internal | casting: cast},
          unit: %{controlled.unit | auras: [], channel_spell: spell.id, channel_object: 30}
      }

      {released, _events} = ControlSync.sync(controlled, 500)
      assert released.internal.casting == nil
      assert released.unit.channel_spell == 0
      assert released.unit.channel_object == 0
      assert Enum.any?(released.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1))
    end

    test "possessing a permanent pet restores its ownership and behavior" do
      holder = holder(:mod_possess_pet)

      pet = %Pet{
        owner_guid: 7,
        kind: :hunter,
        command_state: :follow,
        reaction_state: :aggressive
      }

      mob = %Mob{
        object: %Object{guid: 20},
        unit: %Unit{auras: [holder], faction_template: 14, npc_flags: 3},
        internal: %Internal{pet: pet, spellbook: %{30 => %Spell{id: 30}}}
      }

      {possessed, [grant]} = ControlSync.sync(mob)

      assert possessed.unit.charmed_by == 10
      assert possessed.unit.faction_template == 35
      assert possessed.internal.pet.kind == :hunter
      assert possessed.internal.pet.possessed?
      assert possessed.internal.pet.command_state == :stay
      assert possessed.internal.pet.reaction_state == :passive
      assert is_struct(grant, Effects.ControlGranted)
      assert grant.kind == :possession

      {restored, [release]} = ControlSync.sync(%{possessed | unit: %{possessed.unit | auras: []}})

      assert restored.unit.charmed_by == 0
      assert restored.unit.faction_template == 14
      assert restored.unit.npc_flags == 3
      assert restored.internal.pet.owner_guid == 7
      assert restored.internal.pet.kind == :hunter
      refute restored.internal.pet.possessed?
      assert restored.internal.pet.command_state == :follow
      assert restored.internal.pet.reaction_state == :aggressive
      assert is_struct(release, Effects.ControlReleased)
    end

    test "possessing an ordinary mob creates and removes a temporary control component" do
      mob = %Mob{
        object: %Object{guid: 20},
        unit: %Unit{auras: [holder(:mod_possess)], faction_template: 14, npc_flags: 3},
        internal: %Internal{}
      }

      {possessed, [_grant]} = ControlSync.sync(mob)
      {restored, [_release]} = ControlSync.sync(%{possessed | unit: %{possessed.unit | auras: []}})

      assert possessed.internal.pet.kind == :possessed
      assert possessed.internal.pet.possessed?
      assert (possessed.unit.flags &&& 0x01000000) != 0
      assert (possessed.unit.flags &&& 0x00000008) != 0
      assert restored.internal.pet == nil
      assert restored.unit.faction_template == 14
      assert restored.unit.npc_flags == 3
      assert restored.unit.flags == 0
    end

    test "charming a mob flags it player-controlled and strips the flag on release" do
      mob = %Mob{
        object: %Object{guid: 20},
        unit: %Unit{auras: [holder(:mod_charm)], faction_template: 14, npc_flags: 3, flags: 0x1000},
        internal: %Internal{}
      }

      {charmed, [grant]} = ControlSync.sync(mob)

      assert charmed.internal.pet.kind == :charmed
      assert charmed.internal.pet.owner_guid == 10
      assert charmed.unit.charmed_by == 10
      assert charmed.unit.faction_template == 35
      assert (charmed.unit.flags &&& 0x00000008) != 0
      assert (charmed.unit.flags &&& 0x1000) != 0
      assert is_struct(grant, Effects.ControlGranted)

      unflagged = %{charmed | unit: %{charmed.unit | flags: 8, auras: []}}
      {released, [release]} = ControlSync.sync(unflagged)

      assert released.internal.pet == nil
      assert released.unit.charmed_by == 0
      assert released.unit.faction_template == 14
      assert (released.unit.flags &&& 0x00000008) == 0
      assert (released.unit.flags &&& 0x1000) != 0
      assert is_struct(release, Effects.ControlReleased)
    end

    test "new control stops the mob's current movement path" do
      mob = %Mob{
        object: %Object{guid: 20},
        unit: %Unit{auras: [holder(:mod_possess)], faction_template: 14},
        internal: %Internal{movement_start_time: 500, movement_start_position: {0.0, 0.0, 0.0}},
        movement_block: %MovementBlock{
          position: {0.0, 0.0, 0.0, 0.0},
          spline_nodes: [{10.0, 0.0, 0.0}],
          duration: 2_000,
          movement_flags: 0
        }
      }

      {possessed, events} = ControlSync.sync(mob, 1_000)

      assert possessed.movement_block.spline_nodes == []
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      assert Enum.any?(events, &is_struct(&1, Effects.ControlGranted))
    end
  end

  describe "summoned possession lifecycle" do
    test "removing the owner aura releases the summon described by its effect" do
      spell = %Spell{
        id: 126,
        effects: [
          %Effect{type: :summon_possessed, misc_value: 4277},
          %Effect{type: :apply_aura, aura: :dummy}
        ]
      }

      holder = %Holder{spell: spell, caster_guid: 10, auras: [%Aura{type: :dummy}]}

      character =
        %Character{
          object: %Object{guid: 10},
          unit: %Unit{auras: [holder]},
          internal: %Internal{}
        }
        |> Companion.activate(:possession, %EntityRef{guid: 20, entry: 4277, spell_id: 126})

      {_character, events} = AuraLogic.remove_spells(character, [126], 1_000)

      assert Enum.any?(events, fn event ->
               is_struct(event, Effects.ReleaseControlled) and event.source_guid == 10 and event.target_guid == 20 and
                 event.spell_id == 126
             end)
    end
  end

  defp holder(aura_type) do
    %Holder{
      spell: %Spell{id: 1002},
      caster_guid: 10,
      caster_faction_template: 35,
      auras: [%Aura{type: aura_type}]
    }
  end
end
