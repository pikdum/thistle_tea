defmodule ThistleTea.Game.Entity.Logic.QuestRequirements do
  @moduledoc """
  Validates whether a player can accept a quest: not already active or
  rewarded, race/class masks, minimum level, and prerequisite quest chains.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.QuestLog

  @repeatable_flag 0x1

  def can_take(%Quest{} = quest, ctx), do: can_take(quest, ctx, default_condition_result(quest))

  def can_take(%Quest{} = quest, ctx, :met), do: base_can_take(quest, ctx)
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
      {ctx.level < quest.min_level, :low_level},
      {not minimum_reputation_met?(quest, ctx), :low_reputation},
      {not maximum_reputation_met?(quest, ctx), :high_reputation},
      {not prerequisite_met?(quest, ctx), :missing_prerequisite}
    ]
    |> Enum.find_value(:ok, fn
      {true, reason} -> {:error, reason}
      {false, _reason} -> false
    end)
  end

  def base_can_take?(%Quest{} = quest, ctx), do: base_can_take(quest, ctx) == :ok

  defp rewarded?(%Quest{special_flags: special_flags}, _ctx) when (special_flags &&& @repeatable_flag) != 0, do: false

  defp rewarded?(%Quest{id: id}, ctx), do: MapSet.member?(rewarded_set(ctx), id)

  defp race_allowed?(%Quest{required_races: 0}, _race), do: true

  defp race_allowed?(%Quest{required_races: mask}, race) when is_integer(race), do: (mask &&& 1 <<< (race - 1)) != 0

  defp race_allowed?(%Quest{}, _race), do: false

  defp class_allowed?(%Quest{required_classes: 0}, _class), do: true

  defp class_allowed?(%Quest{required_classes: mask}, class) when is_integer(class),
    do: (mask &&& 1 <<< (class - 1)) != 0

  defp class_allowed?(%Quest{}, _class), do: false

  defp prerequisite_met?(%Quest{prev_quest_id: prev}, ctx) when prev > 0, do: MapSet.member?(rewarded_set(ctx), prev)

  defp prerequisite_met?(%Quest{}, _ctx), do: true

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
