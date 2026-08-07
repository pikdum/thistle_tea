defmodule ThistleTea.Game.Entity.Server.GameObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  test "caught bobbers survive their cast expiry while loot is open" do
    state = %GameObject{internal: %Internal{fishing: %Fishing{consumed?: true}}}

    assert {:noreply, ^state} = GameObjectServer.handle_info(:fishing_expire, state)
  end

  test "owner publishes condition state and updates GO state" do
    db_guid = System.unique_integer([:positive, :monotonic])
    guid = Guid.from_low_guid(:game_object, 21_145, db_guid)

    state = %GameObject{
      object: %Object{guid: guid, entry: 21_145},
      game_object: %GameObjectComponent{state: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }

    pid = start_supervised!({GameObjectServer, state})

    assert Metadata.query(guid, [:db_guid, :go_spawned?, :go_state]) == %{
             db_guid: db_guid,
             go_spawned?: true,
             go_state: 0
           }

    send(pid, {:script_operate_game_object, :close, 0})
    :sys.get_state(pid)

    assert Metadata.query(guid, [:go_state]) == %{go_state: 1}
  end
end
