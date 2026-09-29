defmodule ThistleTea.Game.World.Inbound.Movement do
  @moduledoc "Handles decoded movement, movement acknowledgement, and zone client messages."
  use ThistleTea.Game.Network.Opcodes, [
    :MSG_MOVE_TIME_SKIPPED,
    :MSG_MOVE_KNOCK_BACK,
    :MSG_MOVE_STOP,
    :MSG_MOVE_HEARTBEAT
  ]

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.AreaTriggers
  alias ThistleTea.Game.World.Entity.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.World.Entity.Player.Knockback
  alias ThistleTea.Game.World.Entity.Player.Movement
  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.Mover
  alias ThistleTea.Game.World.Entity.Player.OutdoorPvp
  alias ThistleTea.Game.World.Entity.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.Player.Travel
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.World.Visibility

  @timestamp_modulus 0x1_0000_0000

  def messages do
    [
      Message.CmsgAreatrigger,
      Message.CmsgFarSight,
      Message.CmsgForceMoveRootAck,
      Message.CmsgForceMoveUnrootAck,
      Message.CmsgForceRunBackSpeedChangeAck,
      Message.CmsgForceRunSpeedChangeAck,
      Message.CmsgForceSwimBackSpeedChangeAck,
      Message.CmsgForceSwimSpeedChangeAck,
      Message.CmsgMoveFeatherFallAck,
      Message.CmsgMoveKnockBackAck,
      Message.CmsgMoveNotActiveMover,
      Message.CmsgMoveTeleportAck,
      Message.CmsgMoveTimeSkipped,
      Message.CmsgMoveWaterWalkAck,
      Message.CmsgMoveWorldportAck,
      Message.CmsgSetActiveMover,
      Message.CmsgZoneupdate,
      Message.MsgMove
    ]
  end

  def handle(%Message.CmsgAreatrigger{trigger_id: trigger_id}, state), do: AreaTriggers.handle(state, trigger_id)

  def handle(%Message.CmsgFarSight{operation: operation}, state), do: Visibility.select_viewpoint(state, operation)

  def handle(
        %Message.CmsgForceMoveRootAck{guid: guid, counter: counter, movement_payload: movement_payload},
        %State{} = state
      ) do
    case MovementControl.acknowledge(state, guid, counter, :root) do
      {:ok, state} ->
        state
        |> MovementControl.reconcile_movement(movement_payload, guid)
        |> MovementControl.maybe_finish_repop()

      {:error, state} ->
        state
    end
  end

  def handle(
        %Message.CmsgForceMoveUnrootAck{guid: guid, counter: counter, movement_payload: movement_payload},
        %State{} = state
      ) do
    case MovementControl.acknowledge(state, guid, counter, :unroot) do
      {:ok, state} ->
        state
        |> MovementControl.reconcile_movement(movement_payload, guid)
        |> MovementControl.maybe_finish_repop()

      {:error, state} ->
        state
    end
  end

  def handle(%Message.CmsgForceRunBackSpeedChangeAck{guid: guid, counter: counter, new_speed: speed}, state) do
    MovementControl.acknowledge_speed(state, guid, counter, :run_back_speed, speed)
  end

  def handle(%Message.CmsgForceRunSpeedChangeAck{guid: guid, counter: counter, new_speed: speed}, state) do
    MovementControl.acknowledge_speed(state, guid, counter, :run_speed, speed)
  end

  def handle(%Message.CmsgForceSwimBackSpeedChangeAck{guid: guid, counter: counter, new_speed: speed}, state) do
    MovementControl.acknowledge_speed(state, guid, counter, :swim_back_speed, speed)
  end

  def handle(%Message.CmsgForceSwimSpeedChangeAck{guid: guid, counter: counter, new_speed: speed}, state) do
    MovementControl.acknowledge_speed(state, guid, counter, :swim_speed, speed)
  end

  def handle(%Message.CmsgMoveFeatherFallAck{} = message, %State{} = state) do
    case MovementControl.acknowledge(state, message.guid, message.counter, {:feather_fall, message.apply != 0}) do
      {:ok, state} -> MovementControl.maybe_finish_repop(state)
      {:error, state} -> state
    end
  end

  def handle(%Message.CmsgMoveKnockBackAck{} = message, %State{} = state) do
    Knockback.acknowledge(state, message.guid, message.counter, message.movement_payload)
  end

  def handle(%Message.CmsgMoveNotActiveMover{guid: guid, movement_payload: payload}, state),
    do: Mover.release(state, guid, payload)

  def handle(%Message.CmsgMoveTeleportAck{guid: guid, counter: counter}, %{guid: guid} = state) do
    Travel.teleport_ack(state, guid, counter)
  end

  def handle(%Message.CmsgMoveTeleportAck{}, state), do: state

  def handle(
        %Message.CmsgMoveTimeSkipped{guid: guid, lag: lag},
        %State{
          guid: guid,
          transport_refresh_pending: transport_guid,
          character: %Character{movement_block: %MovementBlock{transport_guid: transport_guid} = movement_block}
        } = state
      )
      when is_integer(transport_guid) and is_integer(lag) do
    movement_block = advance_timestamp(movement_block, lag)
    Outbound.send_packet(UpdateObject.out_of_range([transport_guid]))
    send_transport_refresh(transport_guid)

    %{
      state
      | character: %{state.character | movement_block: movement_block},
        transport_refresh_pending: nil
    }
  end

  def handle(
        %Message.CmsgMoveTimeSkipped{guid: guid, lag: lag},
        %State{guid: guid, character: %Character{} = character} = state
      )
      when is_integer(lag) do
    movement_block = advance_timestamp(character.movement_block, lag)
    broadcast_time_skip(%{state | character: %{character | movement_block: movement_block}}, lag)
    %{state | character: %{character | movement_block: movement_block}}
  end

  def handle(%Message.CmsgMoveTimeSkipped{}, state), do: state

  def handle(%Message.CmsgMoveWaterWalkAck{} = message, %State{} = state) do
    case MovementControl.acknowledge(state, message.guid, message.counter, {:water_walk, message.apply != 0}) do
      {:ok, state} -> MovementControl.maybe_finish_repop(state)
      {:error, state} -> state
    end
  end

  def handle(%Message.CmsgMoveWorldportAck{}, state), do: Travel.worldport_ack(state)

  def handle(%Message.CmsgSetActiveMover{guid: guid}, state), do: Mover.select(state, guid)

  def handle(%Message.CmsgZoneupdate{area: client_zone}, %{ready: true, character: %Character{} = character} = state) do
    %{internal: %{world: world, area: current_area}} = character
    {x, y, z, _o} = character.movement_block.position

    {state, server_zone} =
      case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
        {zone, area} when area != current_area ->
          character = %{character | internal: %{character.internal | area: area}}
          CharacterStore.put(character)
          PartyNotifier.broadcast_stats(state.guid, character)
          {%{state | character: character}, zone}

        {zone, _area} ->
          {state, zone}

        _unknown ->
          {state, PlayerRest.default_zone(world.map_id)}
      end

    zone = server_zone || client_zone

    state =
      if is_integer(zone) and zone > 0 do
        PlayerRest.update_zone(state, zone)
      else
        state
      end

    state |> OutdoorPvp.refresh(server_zone) |> PlayerExploration.check_current()
  end

  def handle(%Message.CmsgZoneupdate{}, state), do: state

  def handle(%Message.MsgMove{} = message, state), do: Movement.handle(message, state)

  defp advance_timestamp(%MovementBlock{timestamp: timestamp} = movement_block, lag)
       when is_integer(timestamp) and timestamp > 0 do
    %{movement_block | timestamp: Integer.mod(timestamp + lag, @timestamp_modulus)}
  end

  defp advance_timestamp(%MovementBlock{} = movement_block, _lag), do: movement_block

  defp broadcast_time_skip(%State{guid: guid, character: %Character{} = character} = state, lag) do
    guid
    |> BinaryUtils.pack_guid()
    |> Kernel.<>(<<lag::little-size(32)>>)
    |> Packet.build(@msg_move_time_skipped)
    |> World.broadcast_packet(character, include_self?: false, recipients: state.player_guids)
  end

  defp send_transport_refresh(transport_guid) do
    case Entity.transport_update(transport_guid) do
      {:ok, %UpdateObject{} = update} ->
        Outbound.send_packet(%{update | has_transport: false})

      _error ->
        :ok
    end
  end
end
