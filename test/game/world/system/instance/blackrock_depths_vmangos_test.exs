defmodule ThistleTea.Game.World.System.Instance.BlackrockDepthsVmangosTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.World.Loader.GameObject, as: GameObjectLoader
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  @moduletag :vmangos_db

  @doors [170_573, 170_574, 170_575, 170_576, 170_577, 174_744, 174_745] ++ Enum.to_list(170_578..170_584)

  describe "instance_blackrock_depths" do
    test "names Blackrock Depths' script" do
      assert ["instance_blackrock_depths"] =
               Mangos.Repo.all(from(m in Mangos.MapTemplate, where: m.entry == 230, select: m.script_name))
    end

    test "every door, brazier and rune the script drives is spawned in the depths" do
      spawned =
        from(g in Mangos.GameObject, where: g.map == 230 and g.id in ^@doors, select: g.id)
        |> Mangos.Repo.all()
        |> MapSet.new()

      assert spawned == MapSet.new(@doors)
    end

    test "the Chest of the Seven waits despawned for Doom'rel" do
      assert %{399_065 => %GameObject{object: %{entry: 169_243}}} = GameObjectLoader.all_blueprints([399_065])
    end

    test "challenging Doom'rel starts the Tomb of the Seven" do
      assert %{1_947 => steps} = ScriptLoader.load_by_ids(Mangos.GossipScript, [1_947])

      assert %ScriptStep{datalong: 3, datalong2: 1, datalong3: 0} =
               Enum.find(steps, &(&1.command == :set_instance_data))

      assert %Mangos.Condition{type: 34, value1: 3, value2: 0} = Mangos.Repo.get(Mangos.Condition, 1_947)
    end

    test "Magmus' warning resolves" do
      assert %Mangos.BroadcastText{} = Mangos.Repo.get(Mangos.BroadcastText, 5_430)
    end
  end
end
