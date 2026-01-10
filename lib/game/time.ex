defmodule ThistleTea.Game.Time do
  def now do
    System.monotonic_time(:millisecond)
  end
end
