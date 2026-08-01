defmodule ThistleTea.Game.Entity.Server.Player.ServerMovement do
  @moduledoc """
  Owns finite server-driven player movement from projection through arrival.
  """

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.BoundaryResult
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World

  @enforce_keys [:token, :timer_ref]
  defstruct [:token, :timer_ref]

  def start(%State{} = state, %Commands.ChargePathResolved{} = command, now \\ Time.now()) do
    state = cancel(state, now)
    character = BoundaryResult.apply(state.character, command)
    World.update_position(character)

    token = make_ref()
    delay = max(command.started_at + command.duration_ms - now, 0)
    timer_ref = Process.send_after(self(), {:server_movement_arrived, token}, delay)

    %{state | character: character, server_movement: %__MODULE__{token: token, timer_ref: timer_ref}}
  end

  def finish(state, token, now \\ Time.now())

  def finish(%State{server_movement: %__MODULE__{token: token, timer_ref: timer_ref}} = state, token, now) do
    Process.cancel_timer(timer_ref)
    character = Movement.finish(state.character, now)
    World.update_position(character)
    %{state | character: character, server_movement: nil}
  end

  def finish(%State{} = state, _token, _now), do: state

  def cancel(%State{character: %Character{}, server_movement: %__MODULE__{timer_ref: timer_ref}} = state, now)
      when is_integer(now) do
    Process.cancel_timer(timer_ref)

    character =
      state.character
      |> Movement.stop(now)
      |> EventSink.emit_pending()

    %{state | character: character, server_movement: nil}
  end

  def cancel(%State{} = state, _now), do: state

  def cancel(%State{} = state), do: cancel(state, Time.now())
end
