defmodule ThistleTea.Game.Entity.Logic.Condition do
  @moduledoc """
  Pure three-valued evaluator for resolved VMangos condition trees.
  """

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Leaf
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.Condition.Result

  @target_facts %{
    aura: :auras,
    item: :item_counts,
    item_with_bank: :item_counts_with_bank,
    item_equipped: :equipped_item_ids,
    reputation_rank_min: :reputation_ranks,
    team: :team,
    skill: :skills,
    quest_rewarded: :rewarded_quests,
    quest_taken: :quest_log,
    argent_dawn_commission_aura: :argent_dawn_commission,
    race_class: :race_class,
    level: :level,
    spell: :spellbook,
    quest_available: :quest_availability,
    quest_none: :quest_log,
    gender: :gender,
    is_player: :kind,
    skill_below: :skills,
    reputation_rank_max: :reputation_ranks,
    moving: :moving,
    has_pet: :has_pet,
    health_percent: :health,
    mana_percent: :mana,
    in_combat: :combat,
    in_group: :group,
    alive: :alive,
    object_spawned: :go_spawned,
    object_loot_state: :loot_state,
    object_go_state: :go_state,
    area_explored: :explored_areas
  }

  @type result :: :met | :unmet | {:unknown, [Reason.t()]}

  def evaluate(%Context{}, nil), do: :met

  def evaluate(%Context{} = context, %Condition{} = condition) do
    case precomputed(context, condition) do
      {:ok, result} -> result
      :missing -> evaluate_resolved(context, condition)
    end
  end

  def compare(actual, expected, mode), do: Result.compare(actual, expected, mode)

  defp precomputed(%Context{environment: %{condition_results: results}}, %Condition{} = condition)
       when is_map(results) do
    case Map.fetch(results, condition_key(condition)) do
      {:ok, result} -> {:ok, precomputed_result(result)}
      :error -> :missing
    end
  end

  defp precomputed(%Context{}, %Condition{}), do: :missing

  defp precomputed_result(result) when result in [:met, :unmet], do: result
  defp precomputed_result({:unknown, reasons}), do: {:unknown, reasons}
  defp precomputed_result(result) when is_boolean(result), do: Result.truth(result)

  defp condition_key(%Condition{entry: entry}) when is_integer(entry) and entry > 0, do: entry
  defp condition_key(%Condition{} = condition), do: condition

  defp evaluate_resolved(context, condition) do
    context = if condition.swap_targets?, do: Context.swap(context), else: context
    result = evaluate_type(context, condition)
    if condition.reverse?, do: Result.negate(result), else: result
  end

  defp evaluate_type(_context, %Condition{type: :none}), do: :met

  defp evaluate_type(context, %Condition{type: :not, children: [child]}) do
    context |> evaluate(child) |> Result.negate()
  end

  defp evaluate_type(context, %Condition{type: :or, children: [_ | _] = children}) do
    children |> Enum.map(&evaluate(context, &1)) |> Result.combine_or()
  end

  defp evaluate_type(context, %Condition{type: :and, children: [_ | _] = children}) do
    children |> Enum.map(&evaluate(context, &1)) |> Result.combine_and()
  end

  defp evaluate_type(_context, %Condition{type: type} = condition) when type in [:not, :or, :and] do
    Result.unknown(condition, :malformed_tree)
  end

  defp evaluate_type(_context, %Condition{type: {:unsupported, :unresolved}} = condition) do
    Result.unknown(condition, :unresolved_tree)
  end

  defp evaluate_type(_context, %Condition{type: {:unsupported, id}} = condition) do
    Result.unknown(condition, {:unsupported_condition_type, id})
  end

  defp evaluate_type(context, %Condition{} = condition) do
    case Leaf.evaluate(context, condition) do
      {:handled, result} -> result
      :unhandled -> Result.unknown(condition, missing_capability(condition.type))
    end
  end

  defp missing_capability(:source_entry), do: {:missing_fact, :source, :entry}
  defp missing_capability(:db_guid), do: {:missing_fact, :source, :db_guid}

  defp missing_capability(type) when is_map_key(@target_facts, type),
    do: {:missing_fact, :target, Map.fetch!(@target_facts, type)}

  defp missing_capability(type), do: {:unsupported_capability, type}
end
