defmodule ThistleTea.Game.Entity.Logic.Racial do
  @moduledoc "Racial combat buffs whose strength is captured from the caster when activated."

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Stats

  @berserking_buff 26_635
  @berserking_state 0x04
  @blood_fury_buff 23_234
  @blood_fury_penalty 23_230

  def berserking(%{object: %{guid: guid}, unit: %Unit{} = unit} = entity) do
    amount = berserking_percent(unit.health, unit.max_health)
    entity = %{entity | unit: %{unit | aura_state: (unit.aura_state || 0) ||| @berserking_state}}

    event =
      Effects.trigger_spell(guid, unit.level || 1, guid, @berserking_buff,
        effect_base_points: %{0 => amount, 1 => amount, 2 => amount}
      )

    {Core.mark_broadcast_update(entity), [event]}
  end

  def berserking_percent(health, maximum) when is_integer(health) and is_integer(maximum) and maximum > 0 do
    percentage = div(max(health, 0) * 100, maximum)
    10 + div(100 - min(max(percentage, 40), 100), 3)
  end

  def berserking_percent(_health, _maximum), do: 10

  def blood_fury(entity, percent, roll \\ &:rand.uniform/0)

  def blood_fury(%Character{object: %{guid: guid}, unit: %Unit{} = unit} = entity, percent, roll)
      when is_integer(percent) and is_function(roll, 0) do
    amount = trunc(Stats.melee_attack_power(unit) * max(percent, 0) / 100 + roll.())
    penalty = Effects.trigger_spell(guid, unit.level || 1, guid, @blood_fury_penalty)

    buffs =
      if amount > 0,
        do: [Effects.trigger_spell(guid, unit.level || 1, guid, @blood_fury_buff, effect_index: 0, base_points: amount)],
        else: []

    {entity, [penalty | buffs]}
  end

  def blood_fury(entity, _percent, _roll), do: {entity, []}
end
