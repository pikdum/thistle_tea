defmodule ThistleTea.Game.World.Loader.VMangosBoundaryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.World.Loader.NpcText, as: NpcTextLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  @moduletag :vmangos_db

  describe "gameobject spawns" do
    test "load through VMangos spawn timing columns" do
      [row | _] =
        {0, 19, 13}
        |> Mangos.GameObject.query_cell([])
        |> Mangos.Repo.all()

      game_object = GameObject.build(row)

      assert game_object.object.entry == row.id
      assert game_object.game_object.display_id == row.game_object_template.display_id
      assert row.spawntimesecsmin == 300
      assert row.spawntimesecsmax == 300
    end
  end

  describe "npc_text" do
    test "loads VMangos broadcast text groups" do
      NpcTextLoader.init()
      :ets.delete_all_objects(NpcTextLoader)

      [group | groups] = NpcTextLoader.get(68)

      assert group.text_0 == "Greetings, $n."
      assert group.text_1 == ""
      assert group.lang == 0
      assert group.em_0 == 0
      assert Enum.all?(groups, &(&1.text_0 == ""))
    end
  end

  describe "quest relations" do
    test "loads VMangos creature giver and ender relation tables" do
      QuestLoader.init()
      :ets.delete_all_objects(QuestLoader)

      assert :ok = QuestLoader.load_all()

      assert 7 in QuestLoader.given_by(197)
      assert 3100 in QuestLoader.given_by(197)
      assert 783 in QuestLoader.ended_by(197)
      assert QuestLoader.get(7).title == "Kobold Camp Cleanup"
    end
  end
end
