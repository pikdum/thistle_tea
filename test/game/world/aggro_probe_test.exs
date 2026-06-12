defmodule ThistleTea.Game.World.AggroProbeTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.SpatialHash

  describe "notify_player_moved/4" do
    test "probes nearby mobs when a player moves" do
      table = table()
      player_guid = player_guid()
      mob_guid = mob_guid()

      Entity.register(mob_guid)
      SpatialHash.update(:mobs, mob_guid, 0, 10.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(mob_guid)
        SpatialHash.remove(:mobs, mob_guid)
      end)

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)

      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end

    test "does not reprobe for tiny movement from the last probed position" do
      table = table()
      player_guid = player_guid()
      mob_guid = mob_guid()

      Entity.register(mob_guid)
      SpatialHash.update(:mobs, mob_guid, 0, 10.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(mob_guid)
        SpatialHash.remove(:mobs, mob_guid)
      end)

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)
      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}

      AggroProbe.notify_player_moved(player_guid, 0, {1.0, 0.0, 0.0}, table)
      refute_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end

    test "probes after map changes even at the same coordinates" do
      table = table()
      player_guid = player_guid()
      old_map_mob_guid = mob_guid()
      new_map_mob_guid = mob_guid()

      Entity.register(old_map_mob_guid)
      Entity.register(new_map_mob_guid)
      SpatialHash.update(:mobs, old_map_mob_guid, 0, 10.0, 0.0, 0.0)
      SpatialHash.update(:mobs, new_map_mob_guid, 1, 10.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(old_map_mob_guid)
        Entity.unregister(new_map_mob_guid)
        SpatialHash.remove(:mobs, old_map_mob_guid)
        SpatialHash.remove(:mobs, new_map_mob_guid)
      end)

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)
      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}

      AggroProbe.notify_player_moved(player_guid, 1, {0.0, 0.0, 0.0}, table)
      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end
  end

  defp table do
    :"aggro_probe_test_#{System.unique_integer([:positive])}"
  end

  defp player_guid do
    Guid.from_low_guid(:player, System.unique_integer([:positive]))
  end

  defp mob_guid do
    Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
  end
end
