defmodule ThistleTea.Game.Core.InstanceScript.Doors do
  @moduledoc """
  Doors whose state follows instance data.

  Each rule pairs a game object entry with a predicate over the copy's data
  that says when it stands open. A data change opens or closes the doors whose
  predicate it flips, and a door that spawns into a copy whose data has moved
  on from the starting values takes the state its predicate gives.
  """

  alias ThistleTea.Game.Core.InstanceScript.Effects

  def changed(rules, previous, current) do
    for {entry, open?} <- rules, open?.(previous) != open?.(current), do: operate(entry, open?.(current))
  end

  def spawned(rules, data, initial, entry) do
    for {^entry, open?} <- rules, open?.(data) != open?.(initial), do: operate(entry, open?.(data))
  end

  def put(rules, data, field, value) do
    updated = Map.put(data, field, value)
    {:ok, value, updated, changed(rules, data, updated)}
  end

  defp operate(entry, true), do: %Effects.OperateGameObject{entry: entry, action: :open}
  defp operate(entry, false), do: %Effects.OperateGameObject{entry: entry, action: :close}
end
