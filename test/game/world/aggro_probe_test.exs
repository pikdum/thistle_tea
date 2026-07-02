defmodule ThistleTea.Game.World.AggroProbeTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "notify_player_moved/4" do
    test "probes nearby hostile mobs when a player moves" do
      table = table()
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_hostile_pair(player_guid, mob_guid, {10.0, 0.0, 0.0})

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)

      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end

    test "does not reprobe for tiny movement from the last probed position" do
      table = table()
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_hostile_pair(player_guid, mob_guid, {10.0, 0.0, 0.0})

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

      put_hostile_pair(player_guid, old_map_mob_guid, {10.0, 0.0, 0.0})
      put_mob(new_map_mob_guid, {10.0, 0.0, 0.0}, map: 1)

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)
      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}

      AggroProbe.notify_player_moved(player_guid, 1, {0.0, 0.0, 0.0}, table)
      assert_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end

    test "does not probe friendly or neutral mobs" do
      table = table()
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_player(player_guid)
      put_mob(mob_guid, {10.0, 0.0, 0.0}, faction_template: wolf())

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)

      refute_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end

    test "does not probe mobs beyond their level-scaled aggro radius" do
      table = table()
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_player(player_guid)
      put_mob(mob_guid, {30.0, 0.0, 0.0})

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)

      refute_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}
    end

    test "does not probe dead mobs or on behalf of dead players" do
      table = table()
      player_guid = player_guid()
      dead_mob_guid = mob_guid()

      put_player(player_guid)
      put_mob(dead_mob_guid, {10.0, 0.0, 0.0}, alive?: false)

      AggroProbe.notify_player_moved(player_guid, 0, {0.0, 0.0, 0.0}, table)
      refute_receive {:"$gen_cast", {:aggro_probe, ^player_guid}}

      ghost_guid = player_guid()
      live_mob_guid = mob_guid()
      put_player(ghost_guid, alive?: false)
      put_mob(live_mob_guid, {10.0, 0.0, 0.0})

      AggroProbe.notify_player_moved(ghost_guid, 0, {0.0, 0.0, 0.0}, table)
      refute_receive {:"$gen_cast", {:aggro_probe, ^ghost_guid}}
    end
  end

  defp put_hostile_pair(player_guid, mob_guid, mob_position) do
    put_player(player_guid)
    put_mob(mob_guid, mob_position)
  end

  defp put_player(player_guid, opts \\ []) do
    Metadata.put(player_guid, %{
      alive?: Keyword.get(opts, :alive?, true),
      faction_template: alliance(),
      unit_flags: 0,
      level: 5
    })

    on_exit(fn -> Metadata.delete(player_guid) end)
  end

  defp put_mob(mob_guid, {x, y, z}, opts \\ []) do
    Entity.register(mob_guid)
    SpatialHash.update(:mobs, mob_guid, Keyword.get(opts, :map, 0), x, y, z)

    Metadata.put(mob_guid, %{
      alive?: Keyword.get(opts, :alive?, true),
      faction_template: Keyword.get(opts, :faction_template, defias()),
      unit_flags: 0,
      level: 5
    })

    on_exit(fn ->
      Entity.unregister(mob_guid)
      SpatialHash.remove(:mobs, mob_guid)
      Metadata.delete(mob_guid)
    end)
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

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp wolf do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0, enemies_0: 28}
  end
end
