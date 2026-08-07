defmodule ThistleTea.Game.Entity.Logic.Condition.Leaf.Unit do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Result
  alias ThistleTea.Game.Entity.Logic.Condition.Subject

  def evaluate(%Context{target: %Subject{aura_ids: aura_ids}}, %Condition{
        type: :aura,
        value1: spell_id,
        value2: effect_index
      })
      when effect_index < 0 and is_struct(aura_ids, MapSet), do: handled(MapSet.member?(aura_ids, spell_id))

  def evaluate(%Context{target: %Subject{aura_effects: effects}}, %Condition{
        type: :aura,
        value1: spell_id,
        value2: effect_index
      })
      when is_struct(effects, MapSet), do: handled(MapSet.member?(effects, {spell_id, effect_index}))

  def evaluate(
        %Context{target: %Subject{level: level}},
        %Condition{type: :level, value1: expected, value2: comparison} = condition
      )
      when is_integer(level), do: {:handled, Result.compare_result(level, expected, comparison, condition)}

  def evaluate(%Context{target: %Subject{gender: gender}}, %Condition{type: :gender, value1: required})
      when is_integer(gender), do: handled(gender == required)

  def evaluate(%Context{target: %Subject{kind: :player}}, %Condition{type: :is_player}), do: handled(true)

  def evaluate(%Context{target: %Subject{player_owned?: owned}}, %Condition{type: :is_player, value1: 1})
      when is_boolean(owned), do: handled(owned)

  def evaluate(%Context{target: %Subject{kind: kind}}, %Condition{type: :is_player, value1: 0}) when not is_nil(kind),
    do: handled(false)

  def evaluate(%Context{target: %Subject{moving?: moving?}}, %Condition{type: :moving}) when is_boolean(moving?),
    do: handled(moving?)

  def evaluate(%Context{target: %Subject{has_pet?: has_pet?}}, %Condition{type: :has_pet}) when is_boolean(has_pet?),
    do: handled(has_pet?)

  def evaluate(
        %Context{target: %Subject{health: health, max_health: maximum}},
        %Condition{type: :health_percent, value1: expected, value2: comparison} = condition
      )
      when is_number(health) and is_number(maximum),
      do: {:handled, Result.percentage(health, maximum, expected, comparison, condition, :health)}

  def evaluate(
        %Context{target: %Subject{mana: mana, max_mana: 0}},
        %Condition{type: :mana_percent, value1: expected, value2: comparison} = condition
      )
      when is_number(mana), do: {:handled, Result.compare_result(100, expected, comparison, condition)}

  def evaluate(
        %Context{target: %Subject{mana: mana, max_mana: maximum}},
        %Condition{type: :mana_percent, value1: expected, value2: comparison} = condition
      )
      when is_number(mana) and is_number(maximum),
      do: {:handled, Result.percentage(mana, maximum, expected, comparison, condition, :mana)}

  def evaluate(%Context{target: %Subject{combat?: combat?}}, %Condition{type: :in_combat}) when is_boolean(combat?),
    do: handled(combat?)

  def evaluate(%Context{target: %Subject{group?: group?}}, %Condition{type: :in_group}) when is_boolean(group?),
    do: handled(group?)

  def evaluate(%Context{target: %Subject{alive?: alive?}}, %Condition{type: :alive}) when is_boolean(alive?),
    do: handled(alive?)

  def evaluate(_context, _condition), do: :unhandled

  defp handled(boolean), do: {:handled, Result.truth(boolean)}
end
