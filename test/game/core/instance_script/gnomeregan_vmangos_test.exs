defmodule ThistleTea.Game.Core.InstanceScript.GnomereganVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Route

  @moduletag :vmangos_db

  describe "Gnomeregan content" do
    test "pins the map adapter, the hidden charges, and the red rockets" do
      assert rows("SELECT script_name FROM map_template WHERE entry = 90") == [["instance_gnomeregan"]]

      assert rows("SELECT guid FROM gameobject WHERE id = 144065 AND spawntimesecsmin < 0 ORDER BY guid") == [
               [3_997_157],
               [3_997_158],
               [3_997_159],
               [3_997_160]
             ]

      assert rows("SELECT guid FROM gameobject WHERE id = 103820 AND map = 90 ORDER BY guid") == [[283], [284], [285]]
    end

    test "each charge sits beside the cave-in it is planted for" do
      assert rows("""
             SELECT c.guid, d.id FROM gameobject c, gameobject d
             WHERE c.id = 144065 AND d.id IN (146085, 146086)
               AND (c.position_x - d.position_x) * (c.position_x - d.position_x)
                 + (c.position_y - d.position_y) * (c.position_y - d.position_y) < 100
             ORDER BY c.guid
             """) == [[3_997_157, 146_085], [3_997_158, 146_085], [3_997_159, 146_086], [3_997_160, 146_086]]
    end

    test "Emi's path follows her script waypoints" do
      [%Route{path: path}] = Enum.filter(CreatureScript.routes(), &(&1.entry == 7_998))

      waypoints =
        "SELECT location_x, location_y, location_z FROM script_waypoint WHERE entry = 7998 ORDER BY pointid"
        |> rows()
        |> Enum.map(fn [x, y, z] -> {x, y, z} end)

      assert Enum.map(path, fn {x, y, z, _wait} -> {x, y, z} end) == waypoints
    end

    test "pins the scripted creatures and their texts" do
      assert rows("SELECT entry, script_name FROM creature_template WHERE entry IN (7800, 7998) ORDER BY entry") == [
               [7_800, "boss_thermaplugg"],
               [7_998, "npc_blastmaster_emi_shortfuse"]
             ]

      assert rows("SELECT count(*) FROM broadcast_text WHERE entry IN (4050, 4137, 4328, 4446, 6173, 6176)") == [[6]]

      assert rows("SELECT script_name FROM spell_template WHERE entry = 12709") == [
               ["spell_gnomeregan_collecting_fallout"]
             ]
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
