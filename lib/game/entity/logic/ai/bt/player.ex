defmodule ThistleTea.Game.Entity.Logic.AI.BT.Player do
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT

  def tree do
    BT.selector([
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
