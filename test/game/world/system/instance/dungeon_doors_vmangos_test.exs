defmodule ThistleTea.Game.World.System.Instance.DungeonDoorsVmangosTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @moduletag :vmangos_db

  test "names each ported dungeon's script" do
    assert rows("SELECT entry, script_name FROM map_template WHERE entry IN (33, 47, 109) ORDER BY entry") == [
             [33, "instance_shadowfang_keep"],
             [47, "instance_razorfen_kraul"],
             [109, "instance_sunken_temple"]
           ]
  end

  test "spawns one shut door for each sealed passage" do
    assert rows(
             "SELECT map, id, state FROM gameobject WHERE id IN (18895, 18971, 18972, 21099, 149431) ORDER BY map, id"
           ) == [
             [33, 18_895, 1],
             [33, 18_971, 1],
             [33, 18_972, 1],
             [47, 21_099, 1],
             [109, 149_431, 1]
           ]
  end

  test "Shadowfang Keep's creatures report the steps that open its doors" do
    assert rows(
             "SELECT id, command, datalong, datalong2 FROM creature_movement_scripts WHERE id IN (384911, 385012) AND command = 37 ORDER BY id"
           ) == [[384_911, 37, 1, 3], [385_012, 37, 1, 3]]

    assert death_writes([3_927, 4_627]) == [[3_927, 4, 3], [4_627, 6, 3]]
    assert rows("SELECT count(*) FROM generic_scripts WHERE id = 9536 AND command = 10 AND datalong = 4627") == [[4]]
  end

  test "Razorfen Kraul's two Ward Keepers guard Agathelos' patrol" do
    assert rows("SELECT count(*) FROM creature WHERE map = 47 AND id = 4625") == [[2]]
    assert death_writes([4_625]) == [[4_625, 1, 3]]
    assert [[count]] = rows("SELECT count(*) FROM creature_movement_template WHERE entry = 4422")
    assert count > 0
  end

  test "Sunken Temple's six protectors guard Jammal'an" do
    assert rows("SELECT id FROM creature WHERE map = 109 AND id BETWEEN 5712 AND 5717 ORDER BY id") ==
             Enum.map(5_712..5_717, &[&1])

    assert death_writes(Enum.to_list(5_712..5_717)) == Enum.map(5_712..5_717, &[&1, 5, 3])
    assert death_writes([5_710]) == [[5_710, 6, 3]]
    assert rows("SELECT count(*) FROM broadcast_text WHERE entry = 4490") == [[1]]
  end

  test "the Scarlet Cathedral's bosses report each stage of their fight" do
    assert rows("SELECT script_name FROM map_template WHERE entry = 189") == [["instance_scarlet_monastery"]]
    assert rows("SELECT guid, id, state FROM gameobject WHERE id = 104600") == [[11_877, 104_600, 1]]

    assert rows("SELECT guid, id FROM creature WHERE guid IN (40029, 39946) ORDER BY guid") == [
             [39_946, 3_977],
             [40_029, 3_976]
           ]

    assert rows("""
           SELECT DISTINCT s.datalong2 FROM creature_ai_events e
           JOIN creature_ai_scripts s ON s.id IN (e.action1_script, e.action2_script, e.action3_script)
           WHERE e.creature_id = 3976 AND s.command = 37 AND s.datalong = 1 ORDER BY s.datalong2
           """) == [[0], [1], [2]]

    assert rows("SELECT datalong, datalong2 FROM generic_scripts WHERE id = 9232 AND command = 37") == [[1, 3]]

    assert rows("SELECT target_type, target_param1, dataint FROM creature_ai_scripts WHERE id = 397702 AND command = 3") ==
             [[12, 2, 101]]

    assert rows("SELECT count(*) FROM broadcast_text WHERE entry = 2973") == [[1]]
  end

  defp death_writes(creatures) do
    rows("""
    SELECT e.creature_id, s.datalong, s.datalong2
    FROM creature_ai_events e
    JOIN creature_ai_scripts s ON s.id IN (e.action1_script, e.action2_script, e.action3_script)
    WHERE e.event_type = 6 AND s.command = 37 AND e.creature_id IN (#{Enum.join(creatures, ",")})
    ORDER BY e.creature_id
    """)
  end

  defp rows(query), do: SQL.query!(Repo, query, []).rows
end
