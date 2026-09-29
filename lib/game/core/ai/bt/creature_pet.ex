defmodule ThistleTea.Game.Core.AI.BT.CreaturePet do
  @moduledoc """
  Creature combat-pet lifetime around the shared pet behavior tree.
  The owner slot must still name this pet, including while its owner is dead.
  """

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Pet
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Mob

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
      alive? or state.internal.in_combat == true or Entity.dead?(state)
    else
      _missing -> false
    end
  end
end
