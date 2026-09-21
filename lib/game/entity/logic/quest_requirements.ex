defmodule ThistleTea.Game.Entity.Logic.QuestRequirements do
  @moduledoc """
  Validates whether a player can accept a quest: not already active or
  rewarded, race/class masks, skills, reputation, and compiled quest dependencies.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.QuestDependencies
  alias ThistleTea.Game.Entity.Data.QuestDependencies.Prerequisite
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.Skills

  def can_take(%Quest{} = quest, ctx), do: can_take(quest, ctx, default_condition_result(quest))

  def can_take(%Quest{} = quest, ctx, :met) do
    case base_can_take(quest, ctx) do
      result when result in [:ok, {:error, :low_level}] ->
        if breadcrumb_conditions_met?(quest, ctx), do: result, else: {:error, :breadcrumb_unavailable}

      error ->
        error
    end
  end

  def can_take(%Quest{}, _ctx, :unmet), do: {:error, :required_condition}

  def can_take(%Quest{}, _ctx, {:unknown, reasons}), do: {:error, {:required_condition_unknown, reasons}}

  def can_take(%Quest{} = quest, ctx, nil), do: can_take(quest, ctx)

  def can_take?(%Quest{} = quest, ctx), do: can_take(quest, ctx) == :ok
  def can_take?(%Quest{} = quest, ctx, condition_result), do: can_take(quest, ctx, condition_result) == :ok

  def base_can_take(%Quest{} = quest, ctx) do
    [
      {QuestLog.active?(ctx.quest_log, quest.id), :already_active},
      {rewarded?(quest, ctx), :already_rewarded},
      {quest.limit_time > 0 and QuestLog.timed?(ctx.quest_log), :timed_quest_active},
      {not race_allowed?(quest, ctx.race), :wrong_race},
      {not class_allowed?(quest, ctx.class), :wrong_class},
      {not skill_met?(quest, ctx), :low_skill},
      {not minimum_reputation_met?(quest, ctx), :low_reputation},
      {not maximum_reputation_met?(quest, ctx), :high_reputation}
    ]
    |> first_failure()
    |> then(fn
      :ok -> check_dependencies(quest, ctx)
      error -> error
    end)
    |> then(fn
      :ok -> if ctx.level < quest.min_level, do: {:error, :low_level}, else: :ok
      error -> error
    end)
  end

  defp first_failure(checks) do
    Enum.find_value(checks, :ok, fn
      {true, reason} -> {:error, reason}
      {false, _reason} -> false
    end)
  end

  def base_can_take?(%Quest{} = quest, ctx), do: base_can_take(quest, ctx) == :ok

  defp rewarded?(%Quest{} = quest, ctx),
    do: not Quest.repeatable?(quest) and MapSet.member?(rewarded_set(ctx), quest.id)

  defp race_allowed?(%Quest{required_races: 0}, _race), do: true

  defp race_allowed?(%Quest{required_races: mask}, race) when is_integer(race), do: (mask &&& 1 <<< (race - 1)) != 0

  defp race_allowed?(%Quest{}, _race), do: false

  defp class_allowed?(%Quest{required_classes: 0}, _class), do: true

  defp class_allowed?(%Quest{required_classes: mask}, class) when is_integer(class),
    do: (mask &&& 1 <<< (class - 1)) != 0

  defp class_allowed?(%Quest{}, _class), do: false

  def condition_quests(%Quest{} = quest), do: [quest | dependencies(quest).breadcrumb_targets]

  defp check_dependencies(quest, ctx) do
    dependencies = dependencies(quest)

    first_failure([
      {not dependencies.valid?, :invalid_dependencies},
      {not prerequisites_met?(dependencies.prerequisites, ctx), :missing_prerequisite},
      {Enum.any?(dependencies.exclusive_quests, &taken?(&1, ctx)), :exclusive_quest},
      {taken?(dependencies.next_chain_quest, ctx), :next_chain_active},
      {Enum.any?(dependencies.previous_chain_quests, &current?(&1, ctx)), :previous_chain_active},
      {Enum.any?(dependencies.dependent_breadcrumb_quests, &outstanding_breadcrumb?(&1, ctx)), :breadcrumb_active},
      {Enum.any?(dependencies.breadcrumb_targets, &(base_can_take(&1, ctx) != :ok)), :breadcrumb_unavailable}
    ])
  end

  defp dependencies(%Quest{dependencies: %QuestDependencies{} = dependencies}), do: dependencies

  defp dependencies(%Quest{} = quest) do
    prerequisites =
      if quest.prev_quest_id == 0 do
        []
      else
        [
          %Prerequisite{
            quest_id: abs(quest.prev_quest_id),
            state: if(quest.prev_quest_id < 0, do: :current, else: :rewarded),
            group_quests: [abs(quest.prev_quest_id)]
          }
        ]
      end

    %QuestDependencies{
      prerequisites: prerequisites,
      next_chain_quest: if(quest.next_quest_in_chain > 0, do: {quest.next_quest_in_chain, false}),
      valid?: quest.breadcrumb_for_quest_id == 0 and quest.exclusive_group == 0
    }
  end

  defp prerequisites_met?([], _ctx), do: true

  defp prerequisites_met?(prerequisites, ctx) do
    Enum.reduce_while(prerequisites, false, fn prerequisite, _result ->
      if prerequisite_state?(prerequisite.quest_id, prerequisite.state, ctx) do
        {:halt, Enum.all?(prerequisite.group_quests, &prerequisite_state?(&1, prerequisite.state, ctx))}
      else
        {:cont, false}
      end
    end)
  end

  defp prerequisite_state?(id, :rewarded, ctx), do: MapSet.member?(rewarded_set(ctx), id)
  defp prerequisite_state?(id, :current, ctx), do: current?(id, ctx)

  defp current?(id, ctx) do
    case QuestLog.get(ctx.quest_log, id) do
      %{status: :incomplete} -> true
      %{status: :complete} -> not MapSet.member?(rewarded_set(ctx), id)
      _ -> false
    end
  end

  defp taken?(nil, _ctx), do: false

  defp taken?({id, repeatable?}, ctx) do
    case QuestLog.get(ctx.quest_log, id) do
      %{status: status} when status in [:incomplete, :complete] -> true
      nil -> not repeatable? and MapSet.member?(rewarded_set(ctx), id)
      _ -> false
    end
  end

  defp outstanding_breadcrumb?({id, repeatable?}, ctx) do
    QuestLog.active?(ctx.quest_log, id) and (repeatable? or not MapSet.member?(rewarded_set(ctx), id))
  end

  defp breadcrumb_conditions_met?(quest, ctx) do
    conditions = Map.get(ctx, :condition_results, %{})
    Enum.all?(dependencies(quest).breadcrumb_targets, &(can_take(&1, ctx, Map.get(conditions, &1.id)) == :ok))
  end

  defp skill_met?(%Quest{required_skill: 0}, _ctx), do: true

  defp skill_met?(%Quest{required_skill: id, required_skill_value: required}, ctx) do
    skills = Map.get(ctx, :skills, %{})
    bonuses = Map.get(ctx, :skill_bonuses, %{})
    {temporary, permanent} = Map.get(bonuses, id, {0, 0})
    value = if Skills.known?(skills, id), do: Skills.value(skills, id) + temporary + permanent, else: 0
    max(value, 0) >= required
  end

  defp minimum_reputation_met?(%Quest{required_min_reputation_faction: faction_id}, _ctx) when faction_id <= 0, do: true

  defp minimum_reputation_met?(
         %Quest{required_min_reputation_faction: faction_id, required_min_reputation_value: required},
         ctx
       ) do
    Map.get(ctx.reputation, faction_id, 0) >= required
  end

  defp maximum_reputation_met?(%Quest{required_max_reputation_faction: faction_id}, _ctx) when faction_id <= 0, do: true

  defp maximum_reputation_met?(
         %Quest{required_max_reputation_faction: faction_id, required_max_reputation_value: maximum},
         ctx
       ) do
    Map.get(ctx.reputation, faction_id, 0) < maximum
  end

  defp rewarded_set(%{rewarded_quests: %MapSet{} = rewarded}), do: rewarded
  defp rewarded_set(_ctx), do: MapSet.new()

  defp default_condition_result(%Quest{required_condition_id: 0}), do: :met

  defp default_condition_result(%Quest{required_condition_id: condition_id, required_condition: condition}) do
    type =
      case condition do
        %Condition{type: type} -> type
        _condition -> {:unsupported, :unresolved}
      end

    {:unknown, [%Reason{entry: condition_id, type: type, capability: :condition_result_missing}]}
  end
end
