defmodule ThistleTea.Game.Core.AI.BT.Player do
  @moduledoc """
  The player behavior tree, ticked from the player owner: reactive
  updates, spell casting, ranged attacks, and melee auto-attack.
  """
  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Charm
  alias ThistleTea.Game.Core.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Core.AI.BT.Confusion
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.BT.Fear
  alias ThistleTea.Game.Core.AI.BT.Ranged, as: RangedBT
  alias ThistleTea.Game.Core.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Core.Combat.Reactive
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Environment.Breathing
  alias ThistleTea.Game.Core.Environment.Fatigue
  alias ThistleTea.Game.Core.Environment.LavaExposure
  alias ThistleTea.Game.Core.Player.Intoxication
  alias ThistleTea.Game.Core.Player.Rest
  alias ThistleTea.Game.Core.Pvp

  def tree do
    BT.selector([
      BT.action(&sobering_tick/3),
      BT.action(&rest_tick/3),
      BT.action(&breathing_tick/3),
      BT.action(&fatigue_tick/3),
      BT.action(&lava_tick/3),
      BT.action(&pvp_tick/3),
      BT.action(&reactive_tick/3),
      BT.action(&Charm.maintain/3),
      BT.action(&Confusion.tick/3),
      BT.action(&Fear.tick/3),
      BT.action(&Charm.tick/3),
      CombatBT.extra_attacks_step(),
      SpellBT.casting_sequence(),
      RangedBT.sequence(),
      CombatBT.melee_sequence(),
      BT.action(&idle/2)
    ])
  end

  defp rest_tick(state, blackboard, %Context{now: now}) do
    {:failure, Rest.tick(state, now), blackboard}
  end

  defp sobering_tick(state, blackboard, %Context{now: now}) do
    {:failure, Intoxication.tick(state, now), blackboard}
  end

  defp breathing_tick(%Character{} = state, blackboard, %Context{} = context) do
    bonus = Random.between(context.random, 0, max((state.unit.level || 1) - 1, 0))

    {:failure, Breathing.update(state, context.liquid_surface, context.now, bonus, context.body_height || 2.0),
     blackboard}
  end

  defp breathing_tick(state, blackboard, _context), do: {:failure, state, blackboard}

  defp fatigue_tick(%Character{} = state, blackboard, %Context{} = context) do
    bonus = Random.between(context.random, 0, max((state.unit.level || 1) - 1, 0))
    {:failure, Fatigue.update(state, context.terrain_liquid, context.now, bonus), blackboard}
  end

  defp fatigue_tick(state, blackboard, _context), do: {:failure, state, blackboard}

  defp lava_tick(%Character{} = state, blackboard, %Context{} = context) do
    damage = Random.between(context.random, 605, 610)
    resistance_roll = Random.between(context.random, 0, 99)
    {:failure, LavaExposure.update(state, context.terrain_liquid, context.now, damage, resistance_roll), blackboard}
  end

  defp lava_tick(state, blackboard, _context), do: {:failure, state, blackboard}

  defp pvp_tick(state, blackboard, %Context{now: now}) do
    {:failure, Pvp.tick(state, now), blackboard}
  end

  defp reactive_tick(%Character{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    {:failure, Reactive.tick(state, now), blackboard}
  end

  defp reactive_tick(state, blackboard, %Context{}), do: {:failure, state, blackboard}

  defp idle(%Character{} = state, %Blackboard{} = blackboard) do
    {:running, state, blackboard}
  end

  defp idle(state, blackboard), do: {:running, state, blackboard}
end
