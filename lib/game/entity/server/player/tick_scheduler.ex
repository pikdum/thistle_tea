defmodule ThistleTea.Game.Entity.Server.Player.TickScheduler do
  @moduledoc """
  Schedules `:player_tick` messages on the owning player process when the tick
  policy (`Logic.AI.Tick`) says the player needs behavior-tree ticking.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Time

  def ensure_scheduled(%{character: %Character{} = character} = state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) ->
        ensure_deadline(state, ref, Tick.player_delay(character, :running, Time.now()))

      _ ->
        if Tick.needs_tick?(character) do
          ref = Process.send_after(self(), :player_tick, 0)
          %{state | player_tick_ref: ref}
        else
          state
        end
    end
  end

  def ensure_scheduled(state), do: state

  defp ensure_deadline(state, ref, delay_ms) do
    case Process.read_timer(ref) do
      remaining_ms when is_integer(remaining_ms) and remaining_ms > delay_ms ->
        Process.cancel_timer(ref)
        %{state | player_tick_ref: Process.send_after(self(), :player_tick, delay_ms)}

      _ ->
        state
    end
  end

  def schedule_now(state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    ref = Process.send_after(self(), :player_tick, 0)
    %{state | player_tick_ref: ref}
  end
end
