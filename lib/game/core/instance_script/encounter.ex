defmodule ThistleTea.Game.Core.InstanceScript.Encounter do
  @moduledoc """
  Reads and settles encounter states in a copy's instance data.

  States follow vmangos: 0 not started, 1 in progress, 2 failed, 3 done. A done
  encounter stays done, so a boss that comes back and starts another fight
  cannot shut the doors its first death opened.
  """

  @not_started 0
  @done 3

  def value(data, field), do: Map.get(data, field, @not_started)

  def done?(data, field), do: value(data, field) == @done

  def settle(data, field, value), do: if(done?(data, field), do: @done, else: value)
end
