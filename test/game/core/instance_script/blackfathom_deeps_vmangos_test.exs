defmodule ThistleTea.Game.Core.InstanceScript.BlackfathomDeepsVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @moduletag :vmangos_db

  describe "Blackfathom Deeps content" do
    test "pins the map adapter, the four fires, and the portal" do
      assert rows("SELECT script_name FROM map_template WHERE entry = 48") == [["instance_blackfathom_deeps"]]

      assert rows("""
             SELECT id, count(*), max(state) FROM gameobject
             WHERE map = 48 AND id BETWEEN 21117 AND 21121 GROUP BY id ORDER BY id
             """) == [[21_117, 1, 1], [21_118, 1, 1], [21_119, 1, 1], [21_120, 1, 1], [21_121, 1, 1]]

      assert rows("SELECT script_name FROM gameobject_template WHERE entry BETWEEN 21118 AND 21121") ==
               List.duplicate(["go_fire_of_akumai"], 4)
    end

    test "pins Kelris reporting his death to the shrine" do
      assert rows("""
             SELECT s.datalong, s.datalong2 FROM creature_ai_scripts s
             JOIN creature_ai_events e ON e.action1_script = s.id
             WHERE e.creature_id = 4832 AND e.event_type = 6 AND s.command = 37
             """) == [[10, 3]]
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
