defmodule ThistleTea.Game.Entity.Logic.Condition.Leaf.Player do
  @moduledoc false

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Result
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestRequirements
  alias ThistleTea.Game.Entity.Logic.Reputation

  def evaluate(%Context{target: %Subject{item_counts: counts}}, %Condition{
        type: :item,
        value1: item_id,
        value2: required
      })
      when is_map(counts), do: handled(Map.get(counts, item_id, 0) >= required)

  def evaluate(%Context{target: %Subject{equipped_item_ids: items}}, %Condition{type: :item_equipped, value1: item_id})
      when is_struct(items, MapSet), do: handled(MapSet.member?(items, item_id))

  def evaluate(%Context{target: %Subject{reputation_ranks: ranks}}, %Condition{
        type: :reputation_rank_min,
        value1: faction_id,
        value2: required_rank
      })
      when is_map(ranks), do: handled(Reputation.rank_value(Map.get(ranks, faction_id, :neutral)) >= required_rank)

  def evaluate(%Context{target: %Subject{reputation_ranks: ranks}}, %Condition{
        type: :reputation_rank_max,
        value1: faction_id,
        value2: maximum_rank
      })
      when is_map(ranks), do: handled(Reputation.rank_value(Map.get(ranks, faction_id, :neutral)) <= maximum_rank)

  def evaluate(%Context{target: %Subject{team: team}}, %Condition{type: :team, value1: required}) when is_integer(team),
    do: handled(team == required)

  def evaluate(%Context{target: %Subject{skills: skills}}, %Condition{type: :skill, value1: skill_id, value2: minimum})
      when is_map(skills), do: handled(Map.has_key?(skills, skill_id) and skill_value(skills, skill_id) >= minimum)

  def evaluate(%Context{target: %Subject{rewarded_quests: rewarded}}, %Condition{
        type: :quest_rewarded,
        value1: quest_id
      })
      when is_struct(rewarded, MapSet), do: handled(MapSet.member?(rewarded, quest_id))

  def evaluate(%Context{target: %Subject{quest_log: quest_log}}, %Condition{
        type: :quest_taken,
        value1: quest_id,
        value2: mode
      })
      when is_map(quest_log), do: handled(quest_taken?(QuestLog.get(quest_log, quest_id), mode))

  def evaluate(%Context{target: %Subject{argent_dawn_commission?: present}}, %Condition{
        type: :argent_dawn_commission_aura
      })
      when is_boolean(present), do: handled(present)

  def evaluate(%Context{target: %Subject{race: race, class: class}}, %Condition{
        type: :race_class,
        value1: race_mask,
        value2: class_mask
      })
      when is_integer(race) and is_integer(class),
      do: handled(mask_matches?(race_mask, race) and mask_matches?(class_mask, class))

  def evaluate(
        %Context{target: %Subject{spellbook: spellbook}},
        %Condition{type: :spell, value1: spell_id, value2: mode} = condition
      )
      when is_map(spellbook) or is_struct(spellbook, MapSet) do
    known? = collection_member?(spellbook, spell_id)

    result =
      case mode do
        0 -> Result.truth(known?)
        1 -> Result.truth(not known?)
        _invalid -> Result.unknown(condition, {:invalid_mode, mode})
      end

    {:handled, result}
  end

  def evaluate(
        %Context{target: %Subject{} = target, quests: quests},
        %Condition{type: :quest_available, value1: quest_id} = condition
      )
      when is_map(quests) do
    case Map.get(quests, quest_id) do
      nil -> {:handled, Result.unknown(condition, {:missing_catalog, :quest, quest_id})}
      quest -> {:handled, quest_available(target, quest, condition)}
    end
  end

  def evaluate(%Context{target: %Subject{quest_log: quest_log, rewarded_quests: rewarded}}, %Condition{
        type: :quest_none,
        value1: quest_id
      })
      when is_map(quest_log) and is_struct(rewarded, MapSet),
      do: handled(QuestLog.get(quest_log, quest_id) == nil and not MapSet.member?(rewarded, quest_id))

  def evaluate(%Context{target: %Subject{item_counts_with_bank: counts}}, %Condition{
        type: :item_with_bank,
        value1: item_id,
        value2: required
      })
      when is_map(counts), do: handled(Map.get(counts, item_id, 0) >= required)

  def evaluate(%Context{target: %Subject{skills: skills}}, %Condition{
        type: :skill_below,
        value1: skill_id,
        value2: maximum
      })
      when is_map(skills) do
    known? = Map.has_key?(skills, skill_id)
    handled(if(maximum == 1, do: not known?, else: known? and skill_value(skills, skill_id) < maximum))
  end

  def evaluate(_context, _condition), do: :unhandled

  defp handled(boolean), do: {:handled, Result.truth(boolean)}

  defp quest_available(
         %Subject{
           level: level,
           race: race,
           class: class,
           quest_log: quest_log,
           rewarded_quests: rewarded,
           reputation: reputation
         },
         quest,
         _condition
       )
       when is_integer(level) and is_integer(race) and is_integer(class) and is_map(quest_log) and
              is_struct(rewarded, MapSet) and is_map(reputation) do
    ctx = %{
      level: level,
      race: race,
      class: class,
      quest_log: quest_log,
      rewarded_quests: rewarded,
      reputation: reputation
    }

    Result.truth(QuestRequirements.can_take?(quest, ctx))
  end

  defp quest_available(_subject, _quest, condition),
    do: Result.unknown(condition, {:missing_facts, :quest_availability})

  defp quest_taken?(%Entry{status: :incomplete}, mode) when mode in [0, 1], do: true
  defp quest_taken?(%Entry{status: :complete}, mode) when mode in [0, 2], do: true
  defp quest_taken?(_entry, _mode), do: false

  defp skill_value(skills, skill_id) do
    case Map.get(skills, skill_id) do
      %{value: value} when is_integer(value) -> value
      value when is_integer(value) -> value
      _missing -> 0
    end
  end

  defp collection_member?(%MapSet{} = collection, value), do: MapSet.member?(collection, value)
  defp collection_member?(collection, value) when is_map(collection), do: Map.has_key?(collection, value)

  defp mask_matches?(0, _value), do: true
  defp mask_matches?(mask, value), do: (mask &&& 1 <<< (value - 1)) != 0
end
