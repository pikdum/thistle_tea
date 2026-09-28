defmodule ThistleTea.Game.Player.CastMovementMapsTest do
  use ExUnit.Case, async: true
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_HEARTBEAT]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps
  @position {-8949.95, -132.49, 83.53, 0.0}

  setup [:caster]

  describe "handle/2" do
    test "turn-only movement cancels the channel and emits its failure", %{state: state} do
      spell = %Spell{id: 900_854, channel_interrupt_flags: 0x10}
      caster = Casting.start_game_object_channel(state.character, 777, spell, 30_000, Time.now())
      state = %{state | character: caster}
      state = move(state, {-8949.95, -132.49, 83.53, 0.1})
      assert state.character.internal.casting == nil
      assert state.character.unit.channel_spell == 0
      assert state.character.unit.channel_object == 0
      assert_received {:"$gen_cast", {:send_packet, %Message.MsgChannelUpdate{time_ms: 0}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x2E}}}
    end

    test "small steps accumulate from the cast origin and respect interrupt flags", %{state: state} do
      for interrupt_flags <- [0, 1] do
        spell = %Spell{id: 900_854, cast_time_ms: 10_000, interrupt_flags: interrupt_flags}
        caster = Casting.start(state.character, spell, Target.self(state.guid), Time.now())
        started = %{state | character: caster}
        small = move(started, {-8949.70, -132.49, 83.53, 0.0})
        assert small.character.internal.casting
        larger = move(small, {-8949.20, -132.49, 83.53, 0.0})
        assert is_nil(larger.character.internal.casting) == (interrupt_flags == 1)
      end
    end
  end

  defp move(state, position) do
    movement = %{state.character.movement_block | position: position, timestamp: 1_000, fall_time: 0}
    message = %Message.MsgMove{opcode: @msg_move_heartbeat, payload: MovementBlock.movement_info_to_binary(movement)}
    updated = Movement.handle(message, state)
    if is_reference(updated.player_tick_ref), do: Process.cancel_timer(updated.player_tick_ref)
    updated
  end

  defp caster(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    {:ok, _} = Entity.register(guid)

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 10, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
      player: %Player{},
      movement_block: struct!(%MovementBlock{position: @position, movement_flags: 0}, MovementBlock.player_speeds()),
      internal: %Internal{world: WorldRef.open(0)}
    }

    on_exit(fn ->
      Presence.leave(character)
      Entity.unregister(guid)
    end)

    %{state: %State{ready: true, guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character}}
  end
end
