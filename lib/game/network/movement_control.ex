defmodule ThistleTea.Game.Network.MovementControl do
  @moduledoc """
  Session-owned sequencing for movement changes that the client acknowledges,
  including deferring spirit-release teleports until earlier changes settle.
  """

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Session

  @ack_timeout_ms 4_000
  @max_counter 0xFFFFFFFF

  def prepare(%Message.SmsgForceMoveRoot{} = packet, %Session{} = state) do
    stamp(state, :root, &%{packet | move_event: &1})
  end

  def prepare(%Message.SmsgForceMoveUnroot{} = packet, %Session{} = state) do
    stamp(state, :unroot, &%{packet | move_event: &1})
  end

  def prepare(%Message.SmsgForceRunSpeedChange{speed: speed} = packet, %Session{} = state) do
    stamp(state, {:run_speed, speed}, &%{packet | move_event: &1})
  end

  def prepare(%Message.MsgMoveTeleportAck{} = packet, %Session{} = state) do
    stamp(state, :teleport, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveWaterWalk{} = packet, %Session{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveLandWalk{} = packet, %Session{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveFeatherFall{} = packet, %Session{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveNormalFall{} = packet, %Session{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveSetHover{} = packet, %Session{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveUnsetHover{} = packet, %Session{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(packet, state), do: {packet, state}

  def acknowledge(%Session{guid: guid} = state, guid, counter, expected) when is_integer(counter) do
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

  def defer_repop(%Session{} = state, {x, y, z, map}) do
    token = make_ref()
    repop = %{token: token, position: {x, y, z}, map: map}
    GenServer.cast(self(), {:finish_repop, token})
    Process.send_after(self(), {:finish_repop_timeout, token}, @ack_timeout_ms)
    %{state | pending_repop: repop}
  end

  def finish_repop(state, token, force? \\ false)

  def finish_repop(%Session{pending_repop: %{token: token} = repop} = state, token, force?) do
    if force? or map_size(state.pending_movement_acks) == 0 do
      {x, y, z} = repop.position
      GenServer.cast(self(), {:start_teleport, x, y, z, repop.map})
      pending = if force?, do: %{}, else: state.pending_movement_acks
      %{state | pending_repop: nil, pending_movement_acks: pending}
    else
      state
    end
  end

  def finish_repop(%Session{} = state, _token, _force?), do: state

  def maybe_finish_repop(%Session{pending_repop: %{token: token}} = state) do
    finish_repop(state, token)
  end

  def maybe_finish_repop(state), do: state

  defp stamp(%Session{} = state, pending_change, build_packet) do
    counter = state.movement_counter
    pending = put_pending(state.pending_movement_acks, counter, pending_change)

    state = %{
      state
      | movement_counter: next_counter(counter),
        pending_movement_acks: pending
    }

    {build_packet.(counter), state}
  end

  defp put_pending(pending, _counter, nil), do: pending
  defp put_pending(pending, counter, change), do: Map.put(pending, counter, change)

  defp matching_ack?({:run_speed, sent}, {:run_speed, received}) do
    is_number(sent) and is_number(received) and abs(sent - received) < 0.01
  end

  defp matching_ack?(pending, expected), do: pending == expected

  defp next_counter(@max_counter), do: 0
  defp next_counter(counter), do: counter + 1
end
