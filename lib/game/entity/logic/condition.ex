defmodule ThistleTea.Game.Entity.Logic.Condition do
  @moduledoc """
  Pure evaluator for resolved `Data.Condition` trees against an entity's own
  state (vmangos `ConditionEntry::Meets` semantics for the supported subset:
  combinators, source entry, and spawn db guid). Unsupported condition types
  are treated as met so gated content keeps firing open, matching the
  behavior before conditions existed.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Condition

  require Logger

  def met?(_state, nil), do: true

  def met?(state, %Condition{reverse?: true} = condition), do: not evaluate(state, condition)
  def met?(state, %Condition{} = condition), do: evaluate(state, condition)

  defp evaluate(_state, %Condition{type: :none}), do: true

  defp evaluate(state, %Condition{type: :not, children: [child]}), do: not met?(state, child)

  defp evaluate(state, %Condition{type: :or, children: children}) do
    Enum.any?(children, &met?(state, &1))
  end

  defp evaluate(state, %Condition{type: :and, children: children}) do
    Enum.all?(children, &met?(state, &1))
  end

  defp evaluate(%{object: %{entry: entry}}, %Condition{type: :source_entry} = condition) do
    matches_any_value?(entry, condition)
  end

  defp evaluate(state, %Condition{type: :db_guid} = condition) do
    case state do
      %{internal: %Internal{creature: %Creature{db_guid: db_guid}}} when is_integer(db_guid) and db_guid > 0 ->
        matches_any_value?(db_guid, condition)

      _ ->
        false
    end
  end

  defp evaluate(_state, %Condition{type: {:unsupported, type}, entry: entry}) do
    Logger.debug("Condition #{entry}: type #{inspect(type)} unimplemented, treating as met")
    true
  end

  defp evaluate(_state, %Condition{}), do: true

  defp matches_any_value?(value, %Condition{value1: v1, value2: v2, value3: v3, value4: v4}) do
    value == v1 or (v2 != 0 and value == v2) or (v3 != 0 and value == v3) or (v4 != 0 and value == v4)
  end
end
