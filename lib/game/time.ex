defmodule ThistleTea.Game.Time do
  @moduledoc """
  The game's clock: monotonic milliseconds, used for all timing and scheduling
  comparisons.
  """
  def now do
    System.monotonic_time(:millisecond)
  end
end
