defmodule ThistleTea.Game.Instance.Eviction do
  @moduledoc "Pure grace-period state for a player who no longer belongs to an instance copy."

  alias ThistleTea.Game.WorldRef

  @delay_ms 60_000
  @enforce_keys [:world, :deadline]
  defstruct @enforce_keys

  def delay_ms, do: @delay_ms

  def refresh(_current, _world, true, _now), do: nil
  def refresh(%__MODULE__{world: world} = current, world, false, _now), do: current

  def refresh(_current, %WorldRef{} = world, false, now) do
    %__MODULE__{world: world, deadline: now + @delay_ms}
  end

  def due?(%__MODULE__{world: world, deadline: deadline}, world, now), do: now >= deadline
  def due?(_current, _world, _now), do: false
end
