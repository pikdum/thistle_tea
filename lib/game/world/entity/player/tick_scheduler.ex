defmodule ThistleTea.Game.World.Entity.Player.TickScheduler do
  @moduledoc """
  Owns player behavior wakes. Reference-bearing messages reject cancelled
  callbacks, and every scheduling path replaces or preserves one owner timer.
  """
  alias ThistleTea.Game.Core.AI.Tick
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Time

  def ensure_scheduled(%{character: %Character{} = character} = state) do
    if Tick.needs_tick?(character) do
      case state.player_tick_ref do
        ref when is_reference(ref) -> ensure_deadline(state, ref, Tick.player_delay(character, :running, Time.now()))
        _ -> schedule_now(state)
      end
    else
      cancel(state)
    end
  end

  def ensure_scheduled(state), do: state

  def after_tick(%{character: %Character{} = character} = state, status, now) do
    if Tick.needs_tick?(character),
      do: schedule(state, Tick.player_delay(character, status, now)),
      else: cancel(state)
  end

  def schedule_now(state), do: schedule(state, 0)

  def schedule(state, delay_ms) do
    state = cancel(state)
    %{state | player_tick_ref: :erlang.start_timer(delay_ms, self(), :player_tick)}
  end

  def cancel(%{player_tick_ref: ref} = state) when is_reference(ref) do
    :erlang.cancel_timer(ref)
    %{state | player_tick_ref: nil}
  end

  def cancel(state), do: state

  defp ensure_deadline(state, ref, delay_ms) do
    case :erlang.read_timer(ref) do
      remaining_ms when is_integer(remaining_ms) and remaining_ms > delay_ms -> schedule(state, delay_ms)
      _ -> state
    end
  end
end
