defmodule ThistleTea.Game.Entity.Server.Player.ServerMovement do
  @moduledoc """
  Owns finite server-driven player movement from projection through arrival.
  """

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.BoundaryResult
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Exploration
  alias ThistleTea.Game.Player.Rest
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Visibility

  @enforce_keys [:token, :timer_ref]
  defstruct [:token, :timer_ref]

  def reconcile(%State{character: character, server_movement: %__MODULE__{timer_ref: ref}} = state) do
    if ControlMovement.active?(character) do
      Process.cancel_timer(ref)
      %{state | server_movement: nil}
    else
      state
    end
  end

  def reconcile(state), do: state

  def advance(%{character: %Character{internal: %{movement_start_time: started}} = character} = state, now)
      when is_integer(started) do
    previous_position = character.movement_block.position
    character = Movement.sync_position(character, now)
    World.update_position(character)
    state = %{state | character: character}

    if previous_position == character.movement_block.position do
      state
    else
      {x, y, z, _} = character.movement_block.position
      AggroProbe.notify_player_moved(character.object.guid, character.internal.world, {x, y, z})
      ChaseWatch.notify_moved(character.object.guid, {x, y, z})

      state
      |> Rest.check_tavern_exit()
      |> Exploration.check_movement(now)
      |> Visibility.refresh_player()
    end
  end

  def advance(state, _now), do: state

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
      |> ControlMovement.reset_navigation()
      |> EventSink.emit_pending()

    %{state | character: character, server_movement: nil}
  end

  def cancel(%State{character: %Character{internal: %{movement_start_time: started}} = character} = state, now)
      when is_integer(started) do
    character = character |> Movement.stop(now) |> ControlMovement.reset_navigation() |> EventSink.emit_pending()
    %{state | character: character}
  end

  def cancel(%State{character: %Character{} = character} = state, _now) do
    if ControlMovement.active?(character),
      do: %{state | character: ControlMovement.reset_navigation(character)},
      else: state
  end

  def cancel(%State{} = state, _now), do: state

  def cancel(%State{} = state), do: cancel(state, Time.now())
end
