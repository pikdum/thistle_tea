defmodule ThistleTea.Game.Entity.Logic.AI.BT.Player do
  @moduledoc """
  The player behavior tree, ticked from the network handler: aura ticks,
  regen, spell casting, and melee auto-attack.
  """
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT

  def tree do
    BT.selector([
      AuraBT.tick_step(),
      RegenBT.tick_step(),
      SpellBT.casting_sequence(),
      CombatBT.melee_sequence(),
      BT.action(&idle/2)
    ])
  end

  defp idle(%Character{} = state, %Blackboard{} = blackboard) do
    {:running, state, blackboard}
  end

  defp idle(state, blackboard), do: {:running, state, blackboard}
end
