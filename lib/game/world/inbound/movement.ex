defmodule ThistleTea.Game.World.Inbound.Movement do
  @moduledoc "Handles decoded movement, movement acknowledgement, and zone client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.AreaTriggers
  alias ThistleTea.Game.World.Entity.Player.Knockback
  alias ThistleTea.Game.World.Entity.Player.Movement
  alias ThistleTea.Game.World.Entity.Player.MovementControl
  alias ThistleTea.Game.World.Entity.Player.Mover
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.Player.Travel
  alias ThistleTea.Game.World.Entity.Player.Zone
  alias ThistleTea.Game.World.Visibility

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

  def handle(%Message.CmsgForceMoveRootAck{} = message, %State{} = state),
    do: MovementControl.acknowledge_controlled(state, message.guid, message.counter, :root, message.movement_payload)

  def handle(%Message.CmsgForceMoveUnrootAck{} = message, %State{} = state),
    do: MovementControl.acknowledge_controlled(state, message.guid, message.counter, :unroot, message.movement_payload)

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

  def handle(%Message.CmsgMoveFeatherFallAck{} = message, %State{} = state),
    do: MovementControl.acknowledge_toggle(state, message.guid, message.counter, {:feather_fall, message.apply != 0})

  def handle(%Message.CmsgMoveKnockBackAck{} = message, %State{} = state) do
    Knockback.acknowledge(state, message.guid, message.counter, message.movement_payload)
  end

  def handle(%Message.CmsgMoveNotActiveMover{guid: guid, movement_payload: payload}, state),
    do: Mover.release(state, guid, payload)

  def handle(%Message.CmsgMoveTeleportAck{guid: guid, counter: counter}, %{guid: guid} = state) do
    Travel.teleport_ack(state, guid, counter)
  end

  def handle(%Message.CmsgMoveTeleportAck{}, state), do: state

  def handle(%Message.CmsgMoveTimeSkipped{guid: guid, lag: lag}, %State{guid: guid} = state),
    do: MovementControl.time_skipped(state, lag)

  def handle(%Message.CmsgMoveTimeSkipped{}, state), do: state

  def handle(%Message.CmsgMoveWaterWalkAck{} = message, %State{} = state),
    do: MovementControl.acknowledge_toggle(state, message.guid, message.counter, {:water_walk, message.apply != 0})

  def handle(%Message.CmsgMoveWorldportAck{}, state), do: Travel.worldport_ack(state)

  def handle(%Message.CmsgSetActiveMover{guid: guid}, state), do: Mover.select(state, guid)

  def handle(%Message.CmsgZoneupdate{area: client_zone}, %{ready: true, character: %Character{}} = state),
    do: Zone.update(state, client_zone)

  def handle(%Message.CmsgZoneupdate{}, state), do: state

  def handle(%Message.MsgMove{} = message, state), do: Movement.handle(message, state)
end
