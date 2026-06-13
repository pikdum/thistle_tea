defmodule ThistleTea.Game.Entity.EventSinkTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

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

    test "tap_cleared clears the entity's own tap metadata", %{mob: mob} do
      guid = mob.object.guid
      Metadata.update(guid, %{tapped_player: 123, tapped_group_id: 7})

      assert ^mob = EventSink.emit(mob, Event.tap_cleared())
      assert Metadata.query(guid, [:tapped_player, :tapped_group_id]) == %{tapped_player: nil, tapped_group_id: nil}
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
        internal: %Internal{map: 0},
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
        internal: %Internal{map: 0},
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
