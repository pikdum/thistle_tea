defmodule ThistleTea.Game.World.Entity.GameObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Component.GameObject, as: GameObjectComponent
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Fishing
  alias ThistleTea.Game.Core.Entity.Component.Internal.Ritual
  alias ThistleTea.Game.Core.Entity.Component.Internal.Summon
  alias ThistleTea.Game.Core.Entity.Component.Internal.Trap
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Profession.Lock
  alias ThistleTea.Game.Core.Profession.Lock.Requirement
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgGameobjectDespawnAnim
  alias ThistleTea.Game.Network.Message.SmsgGameobjectResetState
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.GameObject, as: GameObjectServer
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  test "caught bobbers survive their cast expiry while loot is open" do
    state = %GameObject{internal: %Internal{fishing: %Fishing{consumed?: true}}}

    assert {:noreply, ^state} = GameObjectServer.handle_info(:fishing_expire, state)
  end

  test "owner publishes condition state and updates GO state" do
    db_guid = Unique.integer()
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

  describe "handle_cast/2" do
    test "an altar without a despawn timer uses its spell's channel duration" do
      user_guid = Guid.from_low_guid(:player, Unique.integer())
      object_guid = Guid.from_low_guid(:game_object, Unique.integer(), Unique.integer())
      spell_id = Unique.integer()
      spell = %Spell{id: spell_id, duration_ms: 600_000}
      :ets.insert(SpellLoader, {{:spell, spell_id}, spell})
      {:ok, _} = Entity.register(user_guid)

      on_exit(fn ->
        :ets.delete(SpellLoader, {:spell, spell_id})
        Entity.unregister(user_guid)
      end)

      for {despawn_ms, expected_ms} <- [{0, 600_000}, {nil, 600_000}, {25_000, 25_000}] do
        state = %GameObject{
          object: %Object{guid: object_guid},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %Internal{
            world: WorldRef.instance(30, Unique.integer()),
            ritual: %Ritual{required_participants: 10, animation_spell_id: spell_id},
            summon: %Summon{despawn_in_ms: despawn_ms}
          }
        }

        assert {:noreply, joined} = GameObjectServer.handle_cast({:gameobject_use, user_guid, 60}, state)
        assert MapSet.member?(joined.internal.ritual.users, user_guid)
        assert_receive {:"$gen_cast", {:start_game_object_channel, ^object_guid, ^spell, ^expected_ms}}
      end
    end

    test "creates slow-opening banners before resetting the recipient's interaction cache" do
      lock_id = Unique.integer()
      :ets.insert(LockLoader, {lock_id, %Lock{id: lock_id, requirements: [%Requirement{type: :skill, index: 17}]}})
      on_exit(fn -> :ets.delete(LockLoader, lock_id) end)

      template = %GameObjectTemplate{entry: 178_943, type: 1, flags: 0, size: 1.0, data: [0, lock_id]}
      banner = GameObject.build_summoned(template, WorldRef.instance(999, lock_id), {0.0, 0.0, 0.0, 0.0})
      guid = banner.object.guid
      pid = start_supervised!({GameObjectServer, banner})

      for _projection <- 1..2 do
        Entity.request_update_from(pid, self())
        assert_receive {:"$gen_cast", {:send_packet, created}}
        assert %UpdateObject{update_type: :create_object2, object: %{guid: ^guid}} = created
        assert_receive {:"$gen_cast", {:send_packet, reset}}
        assert %SmsgGameobjectResetState{guid: ^guid} = reset
        assert SmsgGameobjectResetState.to_binary(reset) == <<guid::little-size(64)>>
      end

      :ets.insert(LockLoader, {lock_id, %Lock{id: lock_id, requirements: [%Requirement{type: :skill, index: 1}]}})
      Entity.request_update_from(pid, self())
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{}}}
      :sys.get_state(pid)
      refute_received {:"$gen_cast", {:send_packet, %SmsgGameobjectResetState{}}}
    end

    test "buttons trigger the nearest linked trap in the same copy" do
      entry = Unique.integer()
      world = WorldRef.instance(999, entry)
      button_template = %GameObjectTemplate{entry: entry, type: 1, flags: 0, size: 1.0, data: [0, 0, 0, entry + 1]}
      GameObjectTemplateLoader.put(button_template)
      on_exit(fn -> :ets.delete(GameObjectTemplateLoader, entry) end)
      button = GameObject.build_summoned(button_template, world, {0.0, 0.0, 0.0, 0.0})
      trap_template = %GameObjectTemplate{entry: entry + 1, type: 6, flags: 0, size: 1.0, data: [0, 0, 0, 0]}

      pids =
        for {copy, x} <- [{world, 0.5}, {world, 2.0}, {WorldRef.instance(999, entry + 1), 0.1}] do
          object = GameObject.build_summoned(trap_template, copy, {x, 0.0, 0.0, 0.0})
          pid = start_supervised!({GameObjectServer, object}, id: object.object.guid)
          {pid, :sys.get_state(pid).internal.trap.ready_at}
        end

      button_pid = start_supervised!({GameObjectServer, button}, id: button.object.guid)
      Entity.use_game_object(button.object.guid, 1, 60)
      assert :sys.get_state(button_pid).game_object.state == 0
      [{near, ready_at} | untouched] = pids
      assert %Trap{ready_at: activated_at} = :sys.get_state(near).internal.trap
      assert activated_at > ready_at
      for {pid, initial} <- untouched, do: assert(:sys.get_state(pid).internal.trap.ready_at == initial)
    end

    test "projects a destroyed door state and can reset it" do
      guid = Guid.from_low_guid(:game_object, 16_397, Unique.integer())

      state = %GameObject{
        object: %Object{guid: guid, entry: 16_397},
        game_object: %GameObjectComponent{state: 1},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      pid = start_supervised!({GameObjectServer, state})
      Entity.operate_game_object(guid, :destroy)
      assert :sys.get_state(pid).game_object.state == 2
      assert Metadata.query(guid, [:go_state]) == %{go_state: 2}
      Entity.operate_game_object(guid, :reset)
      assert :sys.get_state(pid).game_object.state == 1
    end
  end

  describe "despawning" do
    setup [:watcher]

    test "a summoned object plays its despawn animation as it goes", %{world: world} do
      template = %GameObjectTemplate{entry: 180_703, type: 1, flags: 0, size: 1.0, data: []}
      firework = GameObject.build_summoned(template, world, {1.0, 2.0, 3.0, 0.0}, despawn_in_ms: 10)
      guid = firework.object.guid
      start_supervised!({GameObjectServer, firework})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgGameobjectDespawnAnim{guid: ^guid}, _opts}}, 1_000
    end

    test "a database spawn leaves without one when its event ends", %{world: world} do
      guid = Guid.from_low_guid(:game_object, 180_754, Unique.integer())

      state = %GameObject{
        object: %Object{guid: guid, entry: 180_754},
        game_object: %GameObjectComponent{state: 1},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
        internal: %Internal{world: world, event: 39}
      }

      pid = start_supervised!({GameObjectServer, state})
      send(pid, {:event_stop, 39})
      :sys.get_state(pid)

      refute_received {:"$gen_cast", {:send_packet, %SmsgGameobjectDespawnAnim{}, _opts}}
    end
  end

  defp watcher(_context) do
    map_id = Unique.integer()
    watcher = Unique.integer()
    {:ok, _} = Entity.register(watcher)
    SpatialHash.update(:players, watcher, map_id, 1.0, 2.0, 3.0)
    on_exit(fn -> SpatialHash.remove(:players, watcher) end)
    %{world: WorldRef.open(map_id)}
  end
end
