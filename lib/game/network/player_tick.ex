defmodule ThistleTea.Game.Network.PlayerTick do
  @moduledoc """
  Schedules `:player_tick` messages on the network handler when the tick
  policy (`Logic.AI.Tick`) says the player needs behavior-tree ticking.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AI.Tick

  def ensure_scheduled(%{character: %Character{} = character} = state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) ->
        state

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

  def schedule_now(state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    ref = Process.send_after(self(), :player_tick, 0)
    %{state | player_tick_ref: ref}
  end
end
