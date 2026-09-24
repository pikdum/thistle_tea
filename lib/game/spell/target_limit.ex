defmodule ThistleTea.Game.Spell.TargetLimit do
  @moduledoc """
  Selects a bounded set from eligible targets in preference order. An explicit
  unit target keeps its slot only when it is already eligible. Zero means no
  limit; duplicate candidates never consume additional slots.
  """

  alias ThistleTea.Game.Spell

  def select(candidates, spell, primary_guid \\ nil)

  def select(candidates, %Spell{max_targets: limit}, primary_guid) when is_integer(limit) and limit > 0 do
    candidates = Enum.uniq(candidates)

    if length(candidates) > limit and primary_guid in candidates do
      Enum.take(Enum.reject(candidates, &(&1 == primary_guid)), limit - 1) ++ [primary_guid]
    else
      Enum.take(candidates, limit)
    end
  end

  def select(candidates, %Spell{}, _primary_guid), do: Enum.uniq(candidates)
end
