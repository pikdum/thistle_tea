defmodule ThistleTea.Game.World.Loader.QuestRewardsVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  @moduletag :vmangos_db

  describe "build/1" do
    test "retains the hidden attunement reward spell and automatic flag quest" do
      quest = Mangos.QuestTemplate |> Mangos.Repo.get_by!(entry: 9123) |> QuestLoader.build()
      assert quest.reward_spell == 0
      assert quest.reward_spell_cast == 28_006
      assert Quest.reward_spell_id(quest) == 28_006
      flag = Mangos.QuestTemplate |> Mangos.Repo.get_by!(entry: 9378) |> QuestLoader.build()
      assert Quest.auto_rewarded?(flag)
      assert flag.min_level == 60
      assert Quest.exploration?(flag)
    end
  end
end
