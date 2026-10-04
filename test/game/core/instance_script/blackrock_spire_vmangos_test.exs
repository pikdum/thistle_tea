defmodule ThistleTea.Game.Core.InstanceScript.BlackrockSpireVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @moduletag :vmangos_db

  @doors [164_725, 175_153, 175_244, 175_245, 175_528, 175_529, 175_530, 175_531, 175_532, 175_533, 175_946, 175_947]

  @rooms [
    [175_194, 40_277],
    [175_194, 40_455],
    [175_195, 40_251],
    [175_196, 40_270],
    [175_196, 45_832],
    [175_197, 40_259],
    [175_197, 40_260],
    [175_198, 40_267],
    [175_198, 40_268],
    [175_198, 45_833],
    [175_199, 40_254],
    [175_199, 40_255],
    [175_199, 45_834],
    [175_200, 40_262],
    [175_200, 40_263]
  ]

  describe "Blackrock Spire content" do
    test "pins the map adapter and the scripted doors" do
      assert rows("SELECT script_name FROM map_template WHERE entry = 229") == [["instance_blackrock_spire"]]

      ids = Enum.join(@doors, ", ")
      assert rows("SELECT id FROM gameobject WHERE map = 229 AND id IN (#{ids}) ORDER BY id") == Enum.map(@doors, &[&1])
    end

    test "each alcove's guardians are the summoners and veterans within ten yards of its rune" do
      assert rows("""
             SELECT r.id, c.guid FROM creature c, gameobject r
             WHERE c.map = 229 AND r.map = 229 AND c.id IN (9818, 9819) AND r.id BETWEEN 175194 AND 175200
               AND (c.position_x - r.position_x) * (c.position_x - r.position_x)
                 + (c.position_y - r.position_y) * (c.position_y - r.position_y)
                 + (c.position_z - r.position_z) * (c.position_z - r.position_z) < 100
             ORDER BY r.id, c.guid
             """) == @rooms
    end

    test "pins the seal, the furnace beast, and the rookery's creatures" do
      assert rows("SELECT name FROM item_template WHERE entry = 12344") == [["Seal of Ascension"]]

      assert rows("SELECT entry FROM creature_template WHERE entry IN (10258, 10264, 10430, 10683) ORDER BY entry") ==
               [[10_258], [10_264], [10_430], [10_683]]

      assert rows("SELECT count(*) FROM broadcast_text WHERE entry = 5538") == [[1]]
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
