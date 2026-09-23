defmodule ThistleTea.Game.Network.MovementControl do
  @moduledoc """
  State-owned sequencing for movement changes that the client acknowledges,
  including deferring spirit-release teleports until earlier changes settle.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Resurrection
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Movement, as: PlayerMovement
  alias ThistleTea.Game.World.Transports

  @ack_timeout_ms 4_000
  @max_counter 0xFFFFFFFF

  def prepare(%Message.SmsgNewWorld{} = packet, %State{} = state) do
    character = Resurrection.expect_arrival(state.character, :worldport)
    {packet, %{state | character: character, pending_movement_acks: %{}, pending_repop: nil}}
  end

  def prepare(%Message.SmsgForceMoveRoot{} = packet, %State{} = state) do
    stamp(state, :root, &%{packet | move_event: &1})
  end

  def prepare(%Message.SmsgForceMoveUnroot{} = packet, %State{} = state) do
    stamp(state, :unroot, &%{packet | move_event: &1})
  end

  def prepare(%Message.SmsgForceRunSpeedChange{} = packet, %State{} = state) do
    stamp_speed(state, packet, :run_speed)
  end

  def prepare(%Message.SmsgForceRunBackSpeedChange{} = packet, %State{} = state) do
    stamp_speed(state, packet, :run_back_speed)
  end

  def prepare(%Message.SmsgForceSwimSpeedChange{} = packet, %State{} = state) do
    stamp_speed(state, packet, :swim_speed)
  end

  def prepare(%Message.SmsgForceSwimBackSpeedChange{} = packet, %State{} = state) do
    stamp_speed(state, packet, :swim_back_speed)
  end

  def prepare(%Message.MsgMoveTeleportAck{} = packet, %State{} = state) do
    kind = if packet.preserve_combat?, do: :combat_teleport, else: :teleport
    pending = Map.reject(state.pending_movement_acks, fn {_counter, kind} -> relocation?(kind) end)
    state = %{state | pending_movement_acks: pending}
    {packet, state} = stamp(state, kind, &%{packet | counter: &1})
    character = Resurrection.expect_arrival(state.character, {:teleport, packet.counter})
    {packet, %{state | character: character}}
  end

  def prepare(%Message.SmsgMoveKnockBack{} = packet, %State{} = state) do
    impulse = {packet.cos_angle, packet.sin_angle, packet.horizontal_speed, packet.vertical_speed}
    stamp(state, {:knockback, packet.guid, impulse}, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveWaterWalk{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveLandWalk{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveFeatherFall{} = packet, %State{} = state) do
    stamp(state, {:feather_fall, true}, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveNormalFall{} = packet, %State{} = state) do
    stamp(state, {:feather_fall, false}, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveSetHover{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveUnsetHover{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(packet, state), do: {packet, state}

  def acknowledge(%State{guid: guid} = state, guid, counter, expected) when is_integer(counter) do
    case Map.fetch(state.pending_movement_acks, counter) do
      {:ok, pending} ->
        if matching_ack?(pending, expected) do
          {:ok, %{state | pending_movement_acks: Map.delete(state.pending_movement_acks, counter)}}
        else
          {:error, state}
        end

      :error ->
        {:error, state}
    end
  end

  def acknowledge(state, _guid, _counter, _expected), do: {:error, state}

  def acknowledge_knockback(%State{} = state, guid, counter, %MovementBlock{} = movement) do
    case Map.fetch(state.pending_movement_acks, counter) do
      {:ok, {:knockback, ^guid, {cos, sin, horizontal, vertical}}} ->
        valid? =
          Bitwise.band(movement.movement_flags || 0, 0x2000) != 0 and
            close?(cos, movement.cos_angle) and close?(sin, movement.sin_angle) and
            close?(horizontal, movement.xy_speed) and close?(vertical, movement.z_speed)

        if valid?,
          do: {:ok, %{state | pending_movement_acks: Map.delete(state.pending_movement_acks, counter)}},
          else: {:error, state}

      _unexpected ->
        {:error, state}
    end
  end

  def acknowledge_teleport(%State{} = state, guid, counter) do
    case Map.get(state.pending_movement_acks, counter) do
      kind when kind in [:teleport, :combat_teleport] ->
        case acknowledge(state, guid, counter, kind) do
          {:ok, state} -> {:ok, state, kind}
          {:error, state} -> {:error, state}
        end

      _invalid ->
        {:error, state}
    end
  end

  def acknowledge_speed(%State{} = state, guid, counter, type, speed) do
    case Map.get(state.pending_movement_acks, counter) do
      {:controlled_speed, ^guid, ^type, sent} ->
        if close?(sent, speed),
          do: maybe_finish_repop(%{state | pending_movement_acks: Map.delete(state.pending_movement_acks, counter)}),
          else: state

      _ ->
        acknowledge_player_speed(state, guid, counter, type, speed)
    end
  end

  defp acknowledge_player_speed(state, guid, counter, type, speed) do
    case acknowledge(state, guid, counter, {type, speed}) do
      {:ok, state} -> maybe_finish_repop(state)
      {:error, state} -> state
    end
  end

  def reconcile_movement(%State{ready: false} = state, _payload), do: state

  def reconcile_movement(%State{character: %Character{} = character} = state, payload) do
    if PlayerMovement.accepts_input?(character), do: reconcile_client_movement(state, payload), else: state
  end

  defp reconcile_client_movement(
         %State{character: %Character{movement_block: %MovementBlock{} = previous} = character} = state,
         payload
       )
       when is_binary(payload) do
    movement_block = MovementBlock.from_binary(payload, previous)

    case Transports.reconcile(character, movement_block) do
      {:ok, movement_block} ->
        state
        |> track_transport_boarding(previous, movement_block)
        |> then(&%{&1 | character: %{character | movement_block: movement_block}})

      {:error, _reason} ->
        state
    end
  end

  def track_transport_boarding(%State{} = state, %MovementBlock{transport_guid: previous_guid}, %MovementBlock{
        transport_guid: current_guid
      }) do
    cond do
      is_integer(current_guid) and current_guid != previous_guid ->
        %{state | transport_refresh_pending: current_guid}

      is_nil(current_guid) ->
        %{state | transport_refresh_pending: nil}

      true ->
        %{state | transport_refresh_pending: nil}
    end
  end

  def defer_repop(%State{} = state, {x, y, z, map}) do
    token = make_ref()
    repop = %{token: token, position: {x, y, z}, map: map}
    GenServer.cast(self(), {:finish_repop, token})
    Process.send_after(self(), {:finish_repop_timeout, token}, @ack_timeout_ms)
    %{state | pending_repop: repop}
  end

  def finish_repop(state, token, force? \\ false)

  def finish_repop(%State{pending_repop: %{token: token} = repop} = state, token, force?) do
    if force? or map_size(state.pending_movement_acks) == 0 do
      {x, y, z} = repop.position
      GenServer.cast(self(), {:start_teleport, x, y, z, repop.map})
      pending = if force?, do: %{}, else: state.pending_movement_acks
      %{state | pending_repop: nil, pending_movement_acks: pending}
    else
      state
    end
  end

  def finish_repop(%State{} = state, _token, _force?), do: state

  def maybe_finish_repop(%State{pending_repop: %{token: token}} = state) do
    finish_repop(state, token)
  end

  def maybe_finish_repop(state), do: state

  defp stamp(%State{} = state, pending_change, build_packet) do
    counter = state.movement_counter
    pending = put_pending(state.pending_movement_acks, counter, pending_change)

    state = %{
      state
      | movement_counter: next_counter(counter),
        pending_movement_acks: pending
    }

    {build_packet.(counter), state}
  end

  defp stamp_speed(state, packet, type) do
    pending =
      if packet.guid == state.guid,
        do: {type, packet.speed},
        else: {:controlled_speed, packet.guid, type, packet.speed}

    stamp(state, pending, &%{packet | move_event: &1})
  end

  defp put_pending(pending, _counter, nil), do: pending
  defp put_pending(pending, counter, change), do: Map.put(pending, counter, change)

  defp relocation?({:knockback, _, _}), do: true
  defp relocation?(kind), do: kind in [:teleport, :combat_teleport]

  defp close?(expected, actual) when is_number(expected) and is_number(actual), do: abs(expected - actual) < 0.01
  defp close?(_expected, _actual), do: false

  defp matching_ack?({type, sent}, {type, received})
       when type in [:run_speed, :run_back_speed, :swim_speed, :swim_back_speed] do
    is_number(sent) and is_number(received) and abs(sent - received) < 0.01
  end

  defp matching_ack?(pending, expected), do: pending == expected

  defp next_counter(@max_counter), do: 0
  defp next_counter(counter), do: counter + 1
end
