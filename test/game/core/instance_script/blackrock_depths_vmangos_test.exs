defmodule ThistleTea.Game.Core.InstanceScript.BlackrockDepthsVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Route

  @moduletag :vmangos_db

  @crowd [8_893, 8_894, 8_895, 8_896, 8_902, 8_904, 8_916]

  describe "Ring of Law content" do
    test "only the jail gate stands open before the fight" do
      gates = "SELECT id, state FROM gameobject WHERE map = 230 AND id BETWEEN 161522 AND 161525 ORDER BY id"
      assert rows(gates) == [[161_522, 1], [161_523, 0], [161_524, 1], [161_525, 1]]
    end

    test "Grimstone walks his script waypoints" do
      [%Route{path: path}] = Enum.filter(CreatureScript.routes(), &(&1.entry == 10_096))

      waypoints =
        "SELECT location_x, location_y, location_z FROM script_waypoint WHERE entry = 10096 ORDER BY pointid"
        |> rows()
        |> Enum.map(fn [x, y, z] -> {x, y, z} end)

      assert Enum.map(path, fn {x, y, z, _wait} -> {x, y, z} end) == waypoints
    end

    test "the crowd sphere holds exactly the spectators vmangos finds in its stands" do
      crowd = Enum.join(@crowd, ", ")

      in_cylinder =
        rows("""
        SELECT count(*) FROM creature WHERE map = 230 AND id IN (#{crowd})
          AND (position_x - 595.78) * (position_x - 595.78) + (position_y + 188.65) * (position_y + 188.65) < 4761
          AND position_z BETWEEN -38.63 AND -28.63
        """)

      in_sphere =
        rows("""
        SELECT count(*) FROM creature WHERE map = 230 AND id IN (#{crowd})
          AND (position_x - 595.78) * (position_x - 595.78) + (position_y + 188.65) * (position_y + 188.65)
            + (position_z + 35.5) * (position_z + 35.5) <= 4761
        """)

      assert in_sphere == in_cylinder
      assert in_sphere == [[54]]
    end

    test "pins Grimstone's lines and the arena's scripts" do
      assert rows("SELECT count(*) FROM broadcast_text WHERE entry BETWEEN 5441 AND 5446") == [[6]]
      assert rows("SELECT script_name FROM creature_template WHERE entry = 10096") == [["npc_grimstone"]]
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
