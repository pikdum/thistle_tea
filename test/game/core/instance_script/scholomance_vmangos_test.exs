defmodule ThistleTea.Game.Core.InstanceScript.ScholomanceVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @moduletag :vmangos_db

  describe "Scholomance content" do
    test "pins the map adapter and the gates it drives open by default" do
      assert rows("SELECT script_name FROM map_template WHERE entry = 289") == [["instance_scholomance"]]

      assert rows("""
             SELECT id, state FROM gameobject
             WHERE map = 289 AND id IN (175570, 177371, 177372, 177373, 177375, 177376, 177377) ORDER BY id
             """) == Enum.map([175_570, 177_371, 177_372, 177_373, 177_375, 177_376, 177_377], &[&1, 0])

      assert rows("SELECT id, state FROM gameobject WHERE map = 289 AND id IN (175167, 175564) ORDER BY id") ==
               [[175_167, 1], [175_564, 1]]
    end

    test "pins Gandling and Kirtonos reporting to the instance" do
      assert rows("""
             SELECT e.creature_id, s.datalong, s.datalong2 FROM creature_ai_scripts s
             JOIN creature_ai_events e ON e.action1_script = s.id
             WHERE e.creature_id IN (1853, 10506) AND s.command = 37 ORDER BY e.creature_id, s.datalong2
             """) == [[1_853, 0, 2], [1_853, 0, 3], [10_506, 7, 2]]
    end

    test "pins the shadow portal rooms' scripted map events" do
      assert rows("""
             SELECT id, count(*) FROM event_scripts
             WHERE id BETWEEN 5618 AND 5623 AND command IN (61, 69, 80) GROUP BY id ORDER BY id
             """) == Enum.map(5_618..5_623, &[&1, 3])
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
