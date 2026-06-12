defmodule ThistleTea.Game.Entity.EventSinkTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.World.Metadata

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
