defmodule ThistleTea.Game.Network.MovementControl do
  @moduledoc """
  State-owned sequencing for movement changes that the client acknowledges,
  including deferring spirit-release teleports until earlier changes settle.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Transports

  @ack_timeout_ms 4_000
  @max_counter 0xFFFFFFFF

  def prepare(%Message.SmsgForceMoveRoot{} = packet, %State{} = state) do
    stamp(state, :root, &%{packet | move_event: &1})
  end

  def prepare(%Message.SmsgForceMoveUnroot{} = packet, %State{} = state) do
    stamp(state, :unroot, &%{packet | move_event: &1})
  end

  def prepare(%Message.SmsgForceRunSpeedChange{speed: speed} = packet, %State{} = state) do
    stamp(state, {:run_speed, speed}, &%{packet | move_event: &1})
  end

  def prepare(%Message.MsgMoveTeleportAck{} = packet, %State{} = state) do
    stamp(state, :teleport, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveWaterWalk{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveLandWalk{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveFeatherFall{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
  end

  def prepare(%Message.SmsgMoveNormalFall{} = packet, %State{} = state) do
    stamp(state, nil, &%{packet | counter: &1})
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

  def reconcile_movement(
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

  defp put_pending(pending, _counter, nil), do: pending
  defp put_pending(pending, counter, change), do: Map.put(pending, counter, change)

  defp matching_ack?({:run_speed, sent}, {:run_speed, received}) do
    is_number(sent) and is_number(received) and abs(sent - received) < 0.01
  end

  defp matching_ack?(pending, expected), do: pending == expected

  defp next_counter(@max_counter), do: 0
  defp next_counter(counter), do: counter + 1
end
