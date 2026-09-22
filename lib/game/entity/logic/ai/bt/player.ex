defmodule ThistleTea.Game.Entity.Logic.AI.BT.Player do
  @moduledoc """
  The player behavior tree, ticked from the player owner: combat sync, reactive
  updates, spell casting, ranged attacks, and melee auto-attack.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Confusion
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Fear
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged, as: RangedBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.Intoxication
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Rest

  def tree do
    BT.selector([
      BT.action(&sobering_tick/3),
      BT.action(&rest_tick/3),
      BT.action(&breathing_tick/3),
      BT.action(&sync_combat/2),
      BT.action(&pvp_tick/3),
      BT.action(&reactive_tick/3),
      BT.action(&Confusion.tick/3),
      BT.action(&Fear.tick/3),
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

  defp sync_combat(%Character{} = state, %Blackboard{} = blackboard) do
    {state, blackboard} = PlayerCombat.sync(state, blackboard)
    {:failure, state, blackboard}
  end

  defp sync_combat(state, blackboard), do: {:failure, state, blackboard}

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
