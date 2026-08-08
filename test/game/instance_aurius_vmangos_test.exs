defmodule ThistleTea.Game.InstanceAuriusVmangosTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @moduletag :vmangos_db

  test "pins Aurius conditions, quests, scripts, and gossip" do
    assert rows(
             "SELECT condition_entry, type, value1, value2, value3 FROM conditions WHERE condition_entry BETWEEN 3755 AND 3758 ORDER BY condition_entry"
           ) == [
             [3_755, 34, 7, 0, 0],
             [3_756, 34, 7, 1, 0],
             [3_757, 34, 7, 2, 0],
             [3_758, 34, 5, 3, 0]
           ]

    assert rows("SELECT entry, RequiredCondition FROM quest_template WHERE entry IN (5122, 5125) ORDER BY entry") == [
             [5_122, 3_755],
             [5_125, 3_757]
           ]

    assert rows(
             "SELECT id, command, datalong, datalong2, datalong3 FROM quest_end_scripts WHERE id = 5122 AND command = 37"
           ) == [
             [5_122, 37, 7, 1, 0]
           ]

    assert rows(
             "SELECT id, command, datalong, datalong2, datalong3, condition_id FROM creature_ai_scripts WHERE id IN (1044002, 1091703) AND command = 37 ORDER BY id, datalong"
           ) == [
             [1_044_002, 37, 5, 2, 0, 0],
             [1_044_002, 37, 7, 2, 0, 3_756],
             [1_091_703, 37, 7, 2, 0, 0]
           ]

    assert rows("SELECT text_id, condition_id FROM gossip_menu WHERE entry = 3043 ORDER BY condition_id") == [
             [3_755, 0],
             [3_756, 3_756],
             [3_757, 3_757]
           ]
  end

  test "pins the partial command and condition inventory" do
    assert rows("SELECT count(*) FROM conditions WHERE type = 34") == [[31]]
    assert rows("SELECT count(*) FROM conditions WHERE type = 18") == [[7]]

    expected = %{
      "creature_ai_scripts" => [107, 105, 2],
      "creature_movement_scripts" => [3, 3, 0],
      "event_scripts" => [1, 1, 0],
      "gameobject_scripts" => [1, 1, 0],
      "generic_scripts" => [15, 14, 1],
      "gossip_scripts" => [5, 5, 0],
      "quest_end_scripts" => [1, 1, 0]
    }

    Enum.each(expected, fn {table, counts} ->
      assert rows("SELECT count(*), sum(datalong3 = 0), sum(datalong3 = 1) FROM #{table} WHERE command = 37") == [
               counts
             ]
    end)
  end

  defp rows(query), do: SQL.query!(Repo, query, []).rows
end
