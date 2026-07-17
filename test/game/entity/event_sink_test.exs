defmodule ThistleTea.Game.Entity.EventSinkTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "emit/2" do
    setup [:metadata_fixtures]

    test "attacker_gained increments the target's attacker count", %{mob: mob, target_guid: target_guid} do
      assert ^mob = EventSink.emit(mob, Event.attacker_gained(target_guid))
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 1}
    end

    test "attacker_lost decrements the target's attacker count", %{mob: mob, target_guid: target_guid} do
      Metadata.update(target_guid, %{attacker_count: 2})

      assert ^mob = EventSink.emit(mob, Event.attacker_lost(target_guid))
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 1}
    end

    test "attacker_lost does not decrement below zero", %{mob: mob, target_guid: target_guid} do
      assert ^mob = EventSink.emit(mob, Event.attacker_lost(target_guid))
      assert Metadata.query(target_guid, [:attacker_count]) == %{attacker_count: 0}
    end

    test "threat ref messages carry the mob incarnation" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(player_guid)

      on_exit(fn -> Entity.unregister(player_guid) end)

      mob = %Mob{object: %Object{guid: mob_guid}, internal: %Internal{spawn: %Spawn{incarnation_id: 7}}}

      assert ^mob = EventSink.emit(mob, Event.threat_ref_gained(player_guid))
      assert_receive {:"$gen_cast", {:threat_ref_gained, ^mob_guid, 7}}
    end

    test "tap_cleared clears the entity's own tap metadata", %{mob: mob} do
      guid = mob.object.guid
      Metadata.update(guid, %{tapped_player: 123, tapped_group_id: 7})

      assert ^mob = EventSink.emit(mob, Event.tap_cleared())
      assert Metadata.query(guid, [:tapped_player, :tapped_group_id]) == %{tapped_player: nil, tapped_group_id: nil}
    end

    test "hearthstone teleports a character to their home bind" do
      character = %Character{internal: %Internal{world: %WorldRef{map_id: 1}, home_bind: {0, -8_946.0, -132.0, 84.0}}}

      assert ^character = EventSink.emit(character, Event.teleport_to_spell_target(8690))
      assert_receive {:"$gen_cast", {:start_teleport, -8_946.0, -132.0, 84.0, 0}}
    end

    test "teleport events preserve their orientation" do
      character = %Character{internal: %Internal{world: %WorldRef{map_id: 0}}}

      assert ^character = EventSink.emit(character, Event.teleport({1.0, 2.0, 3.0, 1.5}))
      assert_receive {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, 1.5, %WorldRef{map_id: 0}}}
    end

    test "feed-pet events preserve the DBC trigger and item target for the player boundary" do
      character = %Character{}
      event = Event.feed_pet(22, 33, 1539, 10.0)

      assert ^character = EventSink.emit(character, event)
      assert_receive {:feed_pet, 22, 33, 1539, 10.0}
    end

    @tag :dbc_db
    test "a released judgement trigger delivers its encoded spell to the victim" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.trigger_spell(caster_guid, 60, target_guid, 20_187)

      assert ^caster = EventSink.emit(caster, event)

      assert_receive {:"$gen_cast",
                      {:receive_spell,
                       %CastContext{
                         caster_guid: ^caster_guid,
                         target_guid: ^target_guid
                       }, %Spell{id: 20_187}}}
    end

    @tag :dbc_db
    test "a custom trigger overrides the selected DBC effect points" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.trigger_spell(caster_guid, 60, caster_guid, 25_503, effect_index: 1, base_points: -16)

      result = EventSink.emit(caster, event)

      assert [%{spell: %Spell{id: 25_503}, auras: [%{amount: -16}]}] = result.unit.auras
    end

    @tag :dbc_db
    test "a resolved party trigger applies to the caster" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, health: 10, max_health: 1_000, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.trigger_spell(caster_guid, 60, caster_guid, 23_455, resolve_targets?: true)
      result = EventSink.emit(caster, event)

      assert result.unit.health > caster.unit.health
    end

    @tag :dbc_db
    test "a remote command trigger stays targeted on the victim" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      victim = %Mob{
        object: %Object{guid: target_guid},
        unit: %Unit{
          level: 1,
          target: caster_guid,
          health: 1_000,
          max_health: 1_000,
          normal_resistance: 0
        },
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.trigger_spell(caster_guid, 60, target_guid, 20_467)

      result = EventSink.emit(victim, event)

      assert result.unit.health < victim.unit.health
    end

    @tag :dbc_db
    test "a local command proc snapshots weapon damage" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(target_guid)

      on_exit(fn -> Entity.unregister(target_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{
          level: 60,
          attack_power: 140,
          base_attack_time: 2_000,
          base_min_damage: 20.0,
          base_max_damage: 30.0,
          min_damage: 30.0,
          max_damage: 40.0
        },
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.trigger_spell(caster_guid, 60, target_guid, 20_424)

      assert ^caster = EventSink.emit(caster, event)

      assert_receive {:"$gen_cast",
                      {:receive_spell,
                       %CastContext{
                         caster_guid: ^caster_guid,
                         target_guid: ^target_guid,
                         weapon_base_min: 20.0,
                         weapon_base_max: 30.0,
                         attack_time_ms: 2_000
                       }, %Spell{id: 20_424}}}
    end

    @tag :dbc_db
    test "a summon-pet event starts an owned pet entity" do
      caster_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(caster_guid)

      on_exit(fn -> Entity.unregister(caster_guid) end)

      caster = %Character{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 50, faction_template: 1, summon: 0},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.summon_pet(caster_guid, 416, 688)

      assert ^caster = EventSink.emit(caster, event)
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %Object{guid: pet_guid}}}}
      assert_receive {:pet_attached, ^pet_guid, 688, pet_spells}
      assert is_pid(Entity.pid(pet_guid))
      assert Enum.any?(pet_spells, &(&1.id == 11_762))

      on_exit(fn -> World.stop_entity(pet_guid) end)
    end

    test "script attack_start schedules a forced attack", %{mob: mob, target_guid: target_guid} do
      assert ^mob = EventSink.emit(mob, Event.attack_start(target_guid))
      assert_receive {:force_attack, ^target_guid}
    end

    test "control transitions notify the controlling entity", %{mob: mob} do
      owner_guid = Guid.from_low_guid(:player, unique_guid())
      Entity.register(owner_guid)
      on_exit(fn -> Entity.unregister(owner_guid) end)
      spell = %Spell{id: 3110}

      assert ^mob = EventSink.emit(mob, Event.control_granted(owner_guid, mob.object.guid, 20_882, [spell]))
      assert_receive {:control_granted, controlled_guid, 20_882, [^spell]}
      assert controlled_guid == mob.object.guid

      assert ^mob = EventSink.emit(mob, Event.control_released(owner_guid, mob.object.guid))
      assert_receive {:control_released, ^controlled_guid}
    end

    test "drop_nearby_threat reconciles mobs missing from player threat refs" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      Entity.register(mob_guid)
      SpatialHash.update(:mobs, mob_guid, 0, 10.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(mob_guid)
        SpatialHash.remove(:mobs, mob_guid)
      end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{level: 60, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      assert ^character = EventSink.emit(character, Event.drop_nearby_threat())
      assert_receive {:"$gen_cast", {:drop_threat, ^player_guid}}
    end

    test "attacker_state_update broadcasts landed hits as normal victim state", %{target_guid: target_guid} do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Entity.register(player_guid)
      SpatialHash.update(:players, player_guid, 0, 0.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(player_guid)
        SpatialHash.remove(:players, player_guid)
      end)

      mob = %Mob{
        object: %Object{guid: mob_guid},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      EventSink.emit(mob, Event.attacker_state_update(mob_guid, target_guid, 12, %{}))

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgAttackerstateupdate{
                         attacker: ^mob_guid,
                         target: ^target_guid,
                         total_damage: 12,
                         damage_state: 1
                       }, _opts}}
    end

    test "periodic_aura_log broadcasts periodic aura log packets", %{target_guid: target_guid} do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      mob_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Entity.register(player_guid)
      SpatialHash.update(:players, player_guid, 0, 0.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(player_guid)
        SpatialHash.remove(:players, player_guid)
      end)

      mob = %Mob{
        object: %Object{guid: mob_guid},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      event = Event.periodic_aura_log(mob_guid, target_guid, %{id: 139}, :periodic_heal, 25)

      EventSink.emit(mob, event)

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgPeriodicauralog{
                         target: ^target_guid,
                         caster: ^mob_guid,
                         spell_id: 139,
                         auras: [%{aura_type: :periodic_heal, amount: 25, misc_value: 0}]
                       }, _opts}}
    end
  end

  defp metadata_fixtures(_context) do
    mob_guid = unique_guid()
    target_guid = unique_guid()

    Metadata.put(mob_guid, %{})
    Metadata.put(target_guid, %{attacker_count: 0})

    on_exit(fn ->
      Metadata.delete(mob_guid)
      Metadata.delete(target_guid)
    end)

    %{mob: %Mob{object: %Object{guid: mob_guid}}, target_guid: target_guid}
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
