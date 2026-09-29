defmodule ThistleTea.Game.World.Entity.Player.PossessionOwnerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Change
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement.SafePosition
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.PossessionOwner
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Inbound
  alias ThistleTea.Game.World.Presence

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

  describe "command/4" do
    test "stops a controlled player's melee without cancelling its ordinary spell", %{state: state, caster: caster} do
      character = state.character
      cast = %Cast{spell: %Spell{id: 116}, phase: :preparing}

      character = %{
        character
        | unit: %{character.unit | target: 123},
          internal: %{
            character.internal
            | casting: cast,
              next_swing_spell: %Spell{id: 78},
              blackboard: %Blackboard{
                combat: %Blackboard.Combat{
                  auto_attacking: true,
                  attack_started: true,
                  auto_attack_target: %TargetRef{guid: 123}
                }
              }
          }
      }

      state = %{state | character: character}
      assert PossessionOwner.command(state, caster + 1, :stop_attack, 0) == state
      stopped = PossessionOwner.command(state, caster, :stop_attack, 0)
      assert stopped.character.unit.target == 0
      assert stopped.character.internal.casting == cast
      assert stopped.character.internal.next_swing_spell == nil
      refute stopped.character.internal.blackboard.combat.auto_attacking
      assert stopped.character.internal.broadcast_update?
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
    test "charm movement controls stay on the victim's connection", %{state: state, caster: caster} do
      character = state.character
      character = put_in(character.internal.possession.kind, :charm)
      guid = state.guid

      EventSink.emit(
        character,
        [
          Effects.movement_root_changed(true),
          Effects.movement_speed_changed(3.5),
          Effects.client_control_changed(true)
        ],
        Context.new(self())
      )

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgForceMoveRoot{guid: ^guid}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgForceRunSpeedChange{guid: ^guid}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgClientControlUpdate{allow_movement?: false}}}
      refute_receive {:controller, {:"$gen_cast", {:send_packet, %Message.SmsgForceMoveRoot{}, _}}}
      refute_receive {:controller, {:"$gen_cast", {:send_packet, %Message.SmsgClientControlUpdate{}, _}}}
      movement = MovementBlock.movement_info_to_binary(character.movement_block)
      state = %{state | character: character}
      assert PossessionOwner.move(state, caster, movement, 0xEE) == state
    end

    test "charm casts route to the explicit owner and stale control cannot cast", %{state: state, caster: caster} do
      character = state.character
      character = put_in(character.internal.possession.kind, :charm)

      effect = %Effects.CharmCast{
        controller_guid: caster,
        control_spell_id: 10_912,
        control_applied_at: 0,
        spell_id: 133,
        target_guid: caster
      }

      EventSink.emit(character, effect, Context.new(self()))
      assert_receive {:charm_cast, ^effect}
      state = %{state | character: character}
      assert Spellcasting.charm_cast(state, %{effect | controller_guid: caster + 1}) == state
      assert Spellcasting.charm_cast(state, %{effect | control_spell_id: 605}) == state
      assert Spellcasting.charm_cast(state, %{effect | control_applied_at: 1}) == state
      assert Spellcasting.charm_cast(state, effect) == state
      released = PossessionOwner.release(state)
      assert Spellcasting.charm_cast(released, effect) == released
    end

    test "PvP flags only dispatch creature commands to creature companions", %{state: state, caster: caster} do
      controller = %{state.character | object: %Object{guid: caster}}

      controlled_player =
        Companion.activate(controller, :possession, %EntityRef{guid: state.guid, entry: 0, spell_id: 605})

      EventSink.emit(controlled_player, %Effects.PvpFlagsChanged{enabled?: true}, Context.new(self()))
      refute_received {:"$gen_cast", {:sync_pvp, _, _}}

      pet = Guid.from_low_guid(:mob, 1, state.guid)
      Entity.register(pet)
      controlled_creature = Companion.activate(controller, :possession, %EntityRef{guid: pet, entry: 1, spell_id: 605})
      EventSink.emit(controlled_creature, %Effects.PvpFlagsChanged{enabled?: true}, Context.new(self()))
      assert_receive {:"$gen_cast", {:sync_pvp, ^caster, true}}
    end

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

      settled = Inbound.handle(ack, state)
      assert settled.pending_movement_acks == %{}
      assert settled.character.movement_block.position == character.movement_block.position
      assert Inbound.handle(ack, settled) == settled
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
      auras: [%Aura{type: :mod_possess}]
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
