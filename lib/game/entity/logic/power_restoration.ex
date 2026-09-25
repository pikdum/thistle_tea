defmodule ThistleTea.Game.Entity.Logic.PowerRestoration do
  @moduledoc """
  Resolves resource grants on the recipient and reports direct spell energizes.
  The resource owner clamps gains against its current capacity and lifecycle.
  """

  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Spell

  def apply(entity, %Effects.GrantPower{misc_value: power, amount: amount} = grant, now)
      when power in 0..4 and is_number(amount) and amount >= 0 do
    if Death.alive?(entity) and Resources.max_power(entity, power) > 0 do
      entity = Resources.gain_power(entity, power, amount)

      case grant.spell do
        %Spell{} = spell ->
          event = %Effects.SpellEnergize{
            source_guid: grant.source_guid,
            target_guid: entity.object.guid,
            spell_id: spell.id,
            power_type: power,
            amount: trunc(amount)
          }

          {Warrior.after_energize(entity, spell, now), [event]}

        nil ->
          {entity, []}
      end
    else
      {entity, []}
    end
  end

  def apply(entity, _grant, _now), do: {entity, []}
end
