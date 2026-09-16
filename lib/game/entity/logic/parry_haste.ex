defmodule ThistleTea.Game.Entity.Logic.ParryHaste do
  @moduledoc """
  Advances the defender's next melee swing after a parried auto-attack.

  Following VMangos DealMeleeDamage, the earlier hand loses up to 40% of
  its unmodified weapon period, with a 20% floor. A swing already inside
  that floor is left alone, and equal deadlines favor the main hand.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat

  def apply(%{internal: %Internal{blackboard: %Blackboard{} = blackboard}} = entity, :parry, now)
      when is_integer(now) do
    {key, deadline, period} = next_hand(entity, blackboard, now)

    if is_integer(deadline) and deadline != 0 and deadline > now and is_integer(period) and period > 0 do
      remaining = deadline - now
      shortened = min(remaining, max(trunc(period * 0.2), trunc(remaining - period * 0.4)))
      blackboard = Blackboard.put_next_at(blackboard, key, shortened, now)
      %{entity | internal: %{entity.internal | blackboard: blackboard}}
    else
      entity
    end
  end

  def apply(entity, _outcome, _now), do: entity

  defp next_hand(%{unit: %Unit{} = unit} = entity, blackboard, now) do
    main = remaining(blackboard, :next_attack_at, now)
    offhand = remaining(blackboard, :next_offhand_attack_at, now)

    if Combat.offhand_damage_range(entity) && offhand < main do
      {:next_offhand_attack_at, blackboard.combat.next_offhand_attack_at, unit.offhand_attack_time}
    else
      {:next_attack_at, blackboard.combat.next_attack_at, unit.base_attack_time}
    end
  end

  defp remaining(blackboard, key, now) do
    if Blackboard.ready_for?(blackboard, key, now), do: 0, else: Blackboard.delay_until(blackboard, key, now)
  end
end
