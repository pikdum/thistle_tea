defmodule ThistleTea.Game.Entity.Logic.Aura.ControlSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Aura.ControlSync
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "sync/1" do
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
      assert grant.type == :control_granted
      assert grant.enabled?

      {restored, [release]} = ControlSync.sync(%{possessed | unit: %{possessed.unit | auras: []}})

      assert restored.unit.charmed_by == 0
      assert restored.unit.faction_template == 14
      assert restored.unit.npc_flags == 3
      assert restored.internal.pet.owner_guid == 7
      assert restored.internal.pet.kind == :hunter
      refute restored.internal.pet.possessed?
      assert restored.internal.pet.command_state == :follow
      assert restored.internal.pet.reaction_state == :aggressive
      assert release.type == :control_released
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
      assert restored.internal.pet == nil
      assert restored.unit.faction_template == 14
      assert restored.unit.npc_flags == 3
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
      assert Enum.any?(events, &(&1.type == :movement_stopped))
      assert Enum.any?(events, &(&1.type == :control_granted))
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

      character = %Character{
        object: %Object{guid: 10},
        unit: %Unit{charm: 20, auras: [holder]},
        internal: %Internal{}
      }

      {_character, events} = AuraLogic.remove_spells(character, [126], 1_000)

      assert Enum.any?(events, fn event ->
               event.type == :release_controlled and event.source_guid == 10 and event.target_guid == 20 and
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
