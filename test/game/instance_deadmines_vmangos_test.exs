defmodule ThistleTea.Game.InstanceDeadminesVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @moduletag :vmangos_db

  describe "Deadmines content" do
    test "pins the map adapter and unique boss doors" do
      assert rows("SELECT script_name FROM map_template WHERE entry = 36") == [["instance_deadmines"]]

      assert rows("SELECT id, count(*) FROM gameobject WHERE map = 36 AND id IN (13965, 16400, 16399) GROUP BY id") == [
               [13_965, 1],
               [16_399, 1],
               [16_400, 1]
             ]
    end

    test "pins the alarm patrol, gunpowder loot and item spell" do
      assert rows("SELECT guid, id FROM creature WHERE map = 36 AND spawntimesecsmin = 43202 ORDER BY guid") == [
               [79_289, 657],
               [79_290, 657]
             ]

      assert rows("SELECT item, ChanceOrQuestChance FROM gameobject_loot_template WHERE entry = 2882") == [
               [5_397, 100.0]
             ]

      assert rows("SELECT spellid_1, spellcharges_1 FROM item_template WHERE entry = 5397") == [[6_250, -1]]
      assert rows("SELECT entry FROM broadcast_text WHERE entry IN (1148, 1149) ORDER BY entry") == [[1_148], [1_149]]
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
