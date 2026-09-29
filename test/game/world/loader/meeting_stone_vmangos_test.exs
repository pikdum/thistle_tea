defmodule ThistleTea.Game.World.Loader.MeetingStoneVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate

  @moduletag :vmangos_db

  describe "build/1" do
    test "the Deadmines stone and innkeeper option queue for the same area" do
      stone = Mangos.Repo.get!(Mangos.GameObjectTemplate, 178_834) |> GameObjectTemplate.build()
      [step] = Mangos.GossipScript.query([2001]) |> Mangos.Repo.all() |> Enum.map(&ScriptStep.build/1)
      assert stone.type == 23
      assert Enum.take(stone.data, 3) == [17, 26, 1581]
      assert step.command == :meeting_stone
      assert step.datalong == 1581
    end
  end
end
