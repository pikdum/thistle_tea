defmodule ThistleTea.Game.Entity.Server.Player.PossessionOwnerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.PossessionOwner
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.WorldRef

  setup [:possessed_player]

  describe "reconcile/1" do
    test "controller process loss removes the aura and restores the victim", %{state: state, caster_pid: caster_pid} do
      state = PossessionOwner.reconcile(state)
      assert state.possession_monitor.pid == caster_pid
      assert PossessionOwner.reconcile(state) == state
      token = state.possession_monitor.token
      Process.exit(caster_pid, :shutdown)
      assert_receive {:DOWN, ^token, :process, ^caster_pid, :shutdown}

      assert {:noreply, restored, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info({:DOWN, token, :process, caster_pid, :shutdown}, state)

      assert restored.character.unit.auras == []
      assert restored.character.unit.charmed_by == 0
      assert restored.character.internal.possession == nil
      assert restored.possession_monitor == nil
    end
  end

  describe "release/3" do
    test "stale releases cannot end a different controller's spell", %{state: state, caster: caster} do
      assert PossessionOwner.release(state, caster + 1, 10_912) == state
      assert PossessionOwner.release(state, caster, 605) == state
      restored = PossessionOwner.release(state, caster, 10_912)
      assert restored.character.internal.possession == nil
      assert restored.character.unit.auras == []
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgClientControlUpdate{allow_movement?: true}}}
      assert_receive {:controller, {:control_released, _}}
    end
  end

  describe "move/4" do
    test "controller movement updates authoritative position and reaches the victim", %{state: state, caster: caster} do
      movement = %{state.character.movement_block | position: {0.0, 0.0, 0.0, 1.0}}
      payload = MovementBlock.movement_info_to_binary(movement)
      assert PossessionOwner.move(state, caster + 1, payload, 0xEE) == state
      moved = PossessionOwner.move(state, caster, payload, 0xEE)
      assert moved.character.movement_block.position == movement.position
      assert World.position(state.guid) == {state.character.internal.world, 0.0, 0.0, 0.0}
      assert_receive {:"$gen_cast", {:send_packet, %Packet{opcode: 0xEE}}}
      refute_receive {:controller, {:"$gen_cast", {:send_packet, %Packet{opcode: 0xEE}}}}
      restored = PossessionOwner.release(moved)
      assert PossessionOwner.move(restored, caster, payload, 0xEE) == restored
      if moved.player_tick_ref, do: Process.cancel_timer(moved.player_tick_ref)
    end

    test "victim acknowledgements cannot move the possessed body", %{state: state} do
      movement = %{state.character.movement_block | position: {100.0, 0.0, 0.0, 0.0}}
      assert MovementControl.reconcile_movement(state, MovementBlock.movement_info_to_binary(movement)) == state
    end
  end

  describe "emit/3" do
    test "root and speed instructions go to the controller", %{state: state} do
      guid = state.guid

      EventSink.emit(
        state.character,
        [Effects.movement_root_changed(true), Effects.movement_speed_changed(3.5)],
        Context.new(self())
      )

      assert_receive {:controller, {:"$gen_cast", {:send_packet, %Message.SmsgForceMoveRoot{guid: ^guid}, _}}}
      assert_receive {:controller, {:"$gen_cast", {:send_packet, %Message.SmsgForceRunSpeedChange{guid: ^guid}, _}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgForceMoveRoot{}}}
    end

    test "fear recovery keeps the victim locked while restoring the controller", %{state: state, caster: caster} do
      EventSink.emit(state.character, Effects.client_control_changed(true), Context.new(self()))
      guid = state.guid
      assert state.character.internal.possession.caster_guid == caster

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgClientControlUpdate{guid: ^guid, allow_movement?: false}}}

      assert_receive {:controller,
                      {:"$gen_cast",
                       {:send_packet, %Message.SmsgClientControlUpdate{guid: ^guid, allow_movement?: true}, _}}}
    end
  end

  describe "acknowledge/4" do
    test "a controlled root acknowledgement never relocates the caster", %{state: victim, caster: caster} do
      character = %{victim.character | object: %Object{guid: caster}}
      character = Companion.activate(character, :possession, %EntityRef{guid: victim.guid, entry: 0, spell_id: 10_912})
      state = %State{guid: caster, character: character, ready: true, active_mover_guid: victim.guid}
      {packet, state} = MovementControl.prepare(%Message.SmsgForceMoveRoot{guid: victim.guid}, state)
      movement = %{victim.character.movement_block | position: {100.0, 0.0, 0.0, 0.0}}

      ack = %Message.CmsgForceMoveRootAck{
        guid: victim.guid,
        counter: packet.move_event,
        movement_payload: MovementBlock.movement_info_to_binary(movement)
      }

      settled = Message.CmsgForceMoveRootAck.handle(ack, state)
      assert settled.pending_movement_acks == %{}
      assert settled.character.movement_block.position == character.movement_block.position
      assert Message.CmsgForceMoveRootAck.handle(ack, settled) == settled
    end
  end

  defp possessed_player(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    caster = System.unique_integer([:positive, :monotonic])
    world = WorldRef.instance(451, guid)
    position = {0.0, 0.0, 0.0, 0.0}
    parent = self()

    caster_pid =
      spawn(fn ->
        Entity.register(caster)
        send(parent, :registered)
        forward(parent)
      end)

    assert_receive :registered
    Entity.register(guid)

    character = %Character{
      object: %Object{guid: guid},
      player: %Player{},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      movement_block: %MovementBlock{position: position},
      internal: %Internal{world: world, safe_position: %SafePosition{world: world, position: position}}
    }

    Presence.enter(character, %{})
    controller = %{character | object: %Object{guid: caster}}
    Presence.enter(controller, %{})

    holder = %Holder{
      spell: %Spell{id: 10_912},
      caster_guid: caster,
      applied_at: 0,
      expires_at: -1,
      negative?: true,
      auras: [%AuraData{type: :mod_possess}]
    }

    {character, _events} = Aura.transition(character, %Change{holders: [holder], cause: :applied, now: 0})
    character = put_in(character.internal.broadcast_update?, false)

    on_exit(fn ->
      Process.exit(caster_pid, :shutdown)
      Presence.leave(character)
      Presence.leave(controller)
    end)

    %{
      state: %State{guid: guid, ready: true, active_mover_guid: guid, character: character},
      caster: caster,
      caster_pid: caster_pid
    }
  end

  defp forward(parent) do
    receive do
      message ->
        send(parent, {:controller, message})
        forward(parent)
    end
  end
end
