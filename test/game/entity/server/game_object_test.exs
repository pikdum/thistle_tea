defmodule ThistleTea.Game.Entity.Server.GameObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer

  test "caught bobbers survive their cast expiry while loot is open" do
    state = %GameObject{internal: %Internal{fishing: %Fishing{consumed?: true}}}

    assert {:noreply, ^state} = GameObjectServer.handle_info(:fishing_expire, state)
  end
end
