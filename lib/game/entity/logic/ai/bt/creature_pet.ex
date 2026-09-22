defmodule ThistleTea.Game.Entity.Logic.AI.BT.CreaturePet do
  @moduledoc """
  Creature combat-pet lifetime around the shared pet behavior tree.
  The owner slot must still name this pet, including while its owner is dead.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects

  def tree, do: BT.selector([BT.action(&lifetime/3), Pet.tree()])

  def lifetime(%Mob{} = state, blackboard, %Context{} = context) do
    if owner_present?(state, context) do
      {:failure, state, blackboard}
    else
      {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}
    end
  end

  defp owner_present?(
         %Mob{object: %{guid: guid}, internal: %{pet: %{owner_guid: owner}, world: world}} = state,
         %Context{perception: perception}
       ) do
    with %{alive?: alive?, pet_guid: ^guid} <- Perception.metadata(perception, owner),
         {^world, _, _, _} <- Perception.position(perception, owner),
         distance when is_number(distance) and distance <= 120.0 <- Perception.distance(perception, owner) do
      alive? or state.internal.in_combat == true or Core.dead?(state)
    else
      _missing -> false
    end
  end
end
