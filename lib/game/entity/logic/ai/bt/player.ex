defmodule ThistleTea.Game.Entity.Logic.AI.BT.Player do
  @moduledoc """
  The player behavior tree, ticked from the network handler: aura ticks,
  regen, spell casting, and melee auto-attack.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged, as: RangedBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Time

  def tree do
    BT.selector([
      BT.action(&sync_combat/2),
      BT.action(&reactive_tick/2),
      AuraBT.tick_step(),
      RegenBT.tick_step(),
      SpellBT.casting_sequence(),
      RangedBT.sequence(),
      CombatBT.melee_sequence(),
      BT.action(&idle/2)
    ])
  end

  defp sync_combat(%Character{} = state, %Blackboard{} = blackboard) do
    {state, blackboard} = PlayerCombat.sync(state, blackboard)
    {:failure, state, blackboard}
  end

  defp sync_combat(state, blackboard), do: {:failure, state, blackboard}

  defp reactive_tick(%Character{} = state, %Blackboard{} = blackboard) do
    {:failure, Reactive.tick(state, Time.now()), blackboard}
  end

  defp reactive_tick(state, blackboard), do: {:failure, state, blackboard}

  defp idle(%Character{} = state, %Blackboard{} = blackboard) do
    {:running, state, blackboard}
  end

  defp idle(state, blackboard), do: {:running, state, blackboard}
end
