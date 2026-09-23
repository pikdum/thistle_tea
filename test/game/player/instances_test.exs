defmodule ThistleTea.Game.Player.InstancesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Instances
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  describe "refresh/2" do
    setup [:build_countdown_state]

    test "starts one grace period and cancels it on valid re-entry", %{state: state} do
      started = Instances.refresh(state, valid?: fn _, _ -> false end, now: 1_000)
      timer = started.instance_eviction
      assert timer.countdown.deadline == 61_000
      assert Process.read_timer(timer.ref) > 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{delay_ms: 60_000}}}
      assert Instances.refresh(started, valid?: fn _, _ -> false end, now: 5_000) == started
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{}}}

      restored = Instances.refresh(started, valid?: fn _, _ -> true end, now: 6_000)
      assert restored.instance_eviction == nil
      assert Process.read_timer(timer.ref) == false
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{delay_ms: 0}}}
      assert Instances.expire(restored, timer.token, now: 100_000) == restored
    end

    test "clears the timer on world transfer and ignores stale notifications", %{state: state} do
      started = Instances.refresh(state, valid?: fn _, _ -> false end, now: 0)
      timer = started.instance_eviction
      next = State.prepare_worldport(started, state.character.internal.world, WorldRef.open(0))
      assert next.instance_eviction == nil
      assert Process.read_timer(timer.ref) == false
      assert Instances.expire(next, timer.token, now: 60_000) == next

      assert {:noreply, ^next} =
               PlayerServer.handle_cast({:instance_membership_changed, WorldRef.instance(33, 999)}, next)
    end

    test "clears the timer on logout", %{state: state} do
      started = Instances.refresh(state, valid?: fn _, _ -> false end, now: 0)
      timer = started.instance_eviction
      bare = %{started | guid: nil, character: nil, ready: false}
      assert State.leave_world(bare).instance_eviction == nil
      assert Process.read_timer(timer.ref) == false
    end

    test "does not start a timer in open worlds or battlegrounds", %{state: state} do
      for world <- [WorldRef.open(0), WorldRef.instance(489, 1)] do
        next = put_in(state.character.internal.world, world)
        assert Instances.refresh(next, valid?: fn _, _ -> flunk("non-dungeon membership queried") end) == next
      end
    end
  end

  describe "expire/3" do
    setup [:build_countdown_state]

    test "teleports home once after the deadline and revalidates eligibility", %{state: state} do
      invalid = [valid?: fn _, _ -> false end]
      started = Instances.refresh(state, invalid ++ [now: 0])
      timer = started.instance_eviction
      assert Instances.expire(started, make_ref(), invalid ++ [now: 60_000]) == started
      assert Instances.expire(started, timer.token, invalid ++ [now: 59_999]) == started
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}
      expired = Instances.expire(started, timer.token, invalid ++ [now: 60_000])
      assert expired.instance_eviction == nil
      assert_receive {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, +0.0, %WorldRef{map_id: 0, instance_id: nil}}}
      assert Instances.expire(expired, timer.token, invalid ++ [now: 60_001]) == expired
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}

      started = Instances.refresh(state, invalid ++ [now: 0])
      restored = Instances.expire(started, started.instance_eviction.token, valid?: fn _, _ -> true end, now: 60_000)
      assert restored.instance_eviction == nil
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}
    end
  end

  describe "restore/3" do
    test "restores reserved battleground copies through their match owner" do
      for map <- [489, 529] do
        previous = :ets.lookup(MapTemplate, map)
        :ets.insert(MapTemplate, {map, 3, nil})

        on_exit(fn ->
          :ets.delete(MapTemplate, map)
          :ets.insert(MapTemplate, previous)
        end)

        world = WorldRef.instance(map, 7)

        character = %Character{
          internal: %Internal{
            world: world,
            area: 3_358,
            home_bind: %HomeBind{map_id: 0, area_id: 12, position: {1.0, 2.0, 3.0}}
          },
          movement_block: %MovementBlock{position: {50.0, 60.0, 70.0, 1.0}}
        }

        dungeon = fn _, _ -> flunk("battleground entered the dungeon admission path") end
        resume = fn ^world, 1 -> {:ok, world} end
        assert Instances.restore(character, 1, resume: dungeon, resume_battleground: resume) == character

        expired = fn ^world, 1 -> {:error, :not_reserved} end
        restored = Instances.restore(character, 1, resume: dungeon, resume_battleground: expired)
        assert restored.internal.world == WorldRef.open(0)
        assert restored.movement_block.position == {1.0, 2.0, 3.0, 0.0}
      end
    end

    test "returns to the home bind when the old instance refuses admission" do
      character = %Character{
        internal: %Internal{
          world: WorldRef.instance(309, 1),
          area: 100,
          home_bind: %HomeBind{map_id: 0, area_id: 12, position: {1.0, 2.0, 3.0}}
        },
        movement_block: %MovementBlock{position: {50.0, 60.0, 70.0, 1.0}}
      }

      for reason <- [:instance_full, :raid_group_required, :too_many_instances, :instance_unavailable] do
        restored = Instances.restore(character, 1, resume: fn %WorldRef{map_id: 309}, 1 -> {:error, reason} end)
        assert restored.internal.world == WorldRef.open(0)
        assert restored.internal.area == 12
        assert restored.movement_block.position == {1.0, 2.0, 3.0, 0.0}
      end

      world = WorldRef.instance(309, 2)
      restored = Instances.restore(character, 1, resume: fn %WorldRef{map_id: 309}, 1 -> {:ok, world} end)
      assert restored.internal.world == world
      assert restored.movement_block == character.movement_block
    end
  end

  describe "teleport admission" do
    test "rejects a raid transfer without moving or disconnecting the player" do
      map = 900_001
      :ets.insert(AreaTrigger, {{:instance_map, map}, true})
      :ets.insert(MapTemplate, {map, 2, nil})

      on_exit(fn ->
        :ets.delete(AreaTrigger, {:instance_map, map})
        :ets.delete(MapTemplate, map)
      end)

      guid = System.unique_integer([:positive])
      state = %State{ready: true, guid: guid, character: %Character{internal: %Internal{world: WorldRef.open(0)}}}
      count = InstanceSystem.count()
      assert PlayerServer.handle_cast({:start_teleport, 1.0, 2.0, 3.0, 0.0, map}, state) == {:noreply, state}
      assert InstanceSystem.count() == count
      assert InstanceSystem.info(guid).current == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{delay_ms: 0, reason: :required}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgNewWorld{}}}
    end
  end

  describe "reject/1" do
    test "projects the distinct vanilla admission failures" do
      for reason <- [:instance_full, :too_many_instances, :instance_unavailable] do
        Instances.reject(reason)
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTransferAborted{reason: ^reason}}}
      end
    end
  end

  defp build_countdown_state(_context) do
    map = 900_002
    :ets.insert(MapTemplate, {map, 1, nil})
    on_exit(fn -> :ets.delete(MapTemplate, map) end)

    character = %Character{
      internal: %Internal{
        world: WorldRef.instance(map, 1),
        home_bind: %HomeBind{map_id: 0, area_id: 12, position: {1.0, 2.0, 3.0}}
      }
    }

    %{state: %State{ready: true, guid: 7, character: character}}
  end
end
