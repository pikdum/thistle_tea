defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.IrontreeWood do
  @moduledoc """
  vmangos `at_irontree_wood`: a hunter carrying the finished Ancient Leaf
  (7632) into Irontree Woods in Felwood wakes Vartrus, Stoma, and Hastat, the
  three ancients who give and take the hunter epic quests, for ten minutes.

  vmangos wakes them only while The Ancient Leaf waits to be turned in, which
  strands the rest of the chain: the ancients give An Introduction, the
  sinew and string quests, and Stave of the Ancients, and take them back
  long after the first ten minutes run out. Here they also wake for a hunter
  who turned in the leaf and has not yet finished the stave.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @irontree_wood 3587
  @ancient_leaf 7632
  @stave_of_the_ancients 7636
  @hunter_mask 0x4
  @complete 2
  @despawn_ms 600_000
  @unique_limit 1
  @unique_distance 100
  @unique 0x04
  @no_attack -1
  @timed_despawn 3

  @ancients [
    {14_524, {6194.55, -1176.35, 369.056, 1.1098}},
    {14_525, {6197.12, -1135.42, 366.31, 5.28025}},
    {14_526, {6245.91, -1165.98, 366.325, 2.60598}}
  ]

  @impl AreaTriggerScript
  def triggers, do: [@irontree_wood]

  @impl AreaTriggerScript
  def steps(_trigger_id, _position), do: Enum.map(@ancients, &wake/1)

  defp wake({entry, position}) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @despawn_ms,
      datalong3: @unique_limit,
      datalong4: @unique_distance,
      dataint: @unique,
      dataint3: @no_attack,
      dataint4: @timed_despawn,
      position: position,
      condition: on_the_chain()
    }
  end

  defp on_the_chain do
    all([
      %Condition{type: :race_class, value2: @hunter_mask},
      any([
        %Condition{type: :quest_taken, value1: @ancient_leaf, value2: @complete},
        all([
          %Condition{type: :quest_rewarded, value1: @ancient_leaf},
          %Condition{type: :quest_rewarded, value1: @stave_of_the_ancients, reverse?: true}
        ])
      ])
    ])
  end

  defp all(children), do: %Condition{type: :and, children: children}
  defp any(children), do: %Condition{type: :or, children: children}
end
