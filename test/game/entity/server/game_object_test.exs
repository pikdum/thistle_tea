defmodule ThistleTea.Game.Entity.Server.GameObjectTest do
  use ExUnit.Case

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer

  describe "start_link/1" do
    test "rejects duplicate entity guids atomically" do
      game_object = game_object(System.unique_integer([:positive]))

      assert {:ok, pid} = GameObjectServer.start_link(game_object)
      assert {:error, {:already_started, ^pid}} = GameObjectServer.start_link(game_object)

      GenServer.stop(pid)
    end
  end

  defp game_object(guid) do
    %GameObject{
      object: %Object{guid: guid},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{map: 0}
    }
  end
end
