defmodule ThistleTea.Game.GameEvent.CreatureData do
  @moduledoc "Loaded world-event changes for one creature spawn."

  defstruct [:event, :entry, :model, :equipment, :spell_start, :spell_end, archetypes: [], spellbook: %{}]

  def select(definitions, events) do
    definitions
    |> Enum.sort_by(& &1.event)
    |> Enum.find(&Enum.member?(events, &1.event))
  end
end
