defmodule ThistleTea.Game.World.Entity.Player.KnockbackTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement.Falling
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Knockback
  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash

  setup [:session]

  describe "acknowledge/4" do
    test "relocates, projects the launch, then accepts a normal landing", %{state: state, movement: movement} do
      observer = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      {:ok, _} = Entity.register(observer)
      world = state.character.internal.world
      SpatialHash.insert(:players, observer, world, 0.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, observer) end)
      state = %{state | player_guids: [observer]}
      payload = MovementBlock.movement_info_to_binary(movement)
      updated = Knockback.acknowledge(state, state.guid, 0, payload)
      assert updated.pending_movement_acks == %{}
      assert updated.character.movement_block.position == movement.position
      assert updated.character.internal.fall.height == 1.0
      assert World.position(state.guid) == {world, 2.0, 0.0, 1.0}
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgMoveKnockBack{movement_block: projected}, _}}
      assert projected.position == movement.position
      assert projected.xy_speed == 12.0
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMoveKnockBack{}, _}}

      landing = %{movement | position: {10.0, 0.0, 0.0, 0.0}, movement_flags: 0, fall_time: 1000}

      updated =
        Message.MsgMove.handle(
          %Message.MsgMove{opcode: 0xC9, payload: MovementBlock.movement_info_to_binary(landing)},
          updated
        )

      assert updated.character.internal.fall == nil
      assert updated.character.unit.health == 100
      assert World.position(state.guid) == {world, 10.0, 0.0, 0.0}
    end

    test "death and teleport prevent late acknowledgement relocation", %{state: state, movement: movement} do
      payload = MovementBlock.movement_info_to_binary(movement)
      dead = put_in(state.character.unit.health, 0)
      settled = Knockback.acknowledge(dead, dead.guid, 0, payload)
      assert settled.pending_movement_acks == %{}
      assert settled.character.movement_block.position == dead.character.movement_block.position
      {_, teleported} = MovementControl.prepare(%Message.MsgMoveTeleportAck{guid: state.guid}, state)
      assert Knockback.acknowledge(teleported, state.guid, 0, payload) == teleported
    end

    test "routes a possessed mover and discards its reply after control ends", %{state: state, movement: movement} do
      mover = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))
      {:ok, _} = Entity.register(mover)
      character = Companion.activate(state.character, :possession, %EntityRef{guid: mover, entry: 1, spell_id: 126})
      state = %{state | character: character, active_mover_guid: mover}
      {packet, state} = MovementControl.prepare(%{packet(mover) | guid: mover}, state)
      payload = MovementBlock.movement_info_to_binary(movement)
      updated = Knockback.acknowledge(state, mover, packet.counter, payload)
      assert updated.character.movement_block == state.character.movement_block
      assert_receive {:controlled_move, _, ^payload, 0xF1}

      released = %{state | active_mover_guid: state.guid}
      settled = Knockback.acknowledge(released, mover, packet.counter, payload)
      refute Map.has_key?(settled.pending_movement_acks, packet.counter)
      refute_receive {:controlled_move, _, _, _}
    end
  end

  defp session(_) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    {:ok, _} = Entity.register(guid)

    character = %Character{
      object: %Object{guid: guid},
      player: %Player{flags: 0},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      internal: %Internal{world: WorldRef.open(0), fall: %Falling{height: 100.0, far?: true}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    on_exit(fn -> Presence.leave(character) end)

    state = %State{
      guid: guid,
      ready: true,
      character: character,
      player_guids: [],
      next_exploration_check_at: Time.now() + 60_000
    }

    {_, state} = MovementControl.prepare(packet(guid), state)

    movement = %MovementBlock{
      position: {2.0, 0.0, 1.0, 0.0},
      movement_flags: 0x2000,
      cos_angle: 1.0,
      sin_angle: 0.0,
      xy_speed: 12.0,
      z_speed: -7.0,
      timestamp: 100,
      fall_time: 0
    }

    %{state: state, movement: movement}
  end

  defp packet(guid),
    do: %Message.SmsgMoveKnockBack{
      guid: guid,
      cos_angle: 1.0,
      sin_angle: 0.0,
      horizontal_speed: 12.0,
      vertical_speed: -7.0
    }
end
