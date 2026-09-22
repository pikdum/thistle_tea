defmodule ThistleTea.Game.Entity.Logic.AI.BT.Guardian do
  @moduledoc """
  Guardian lifetime around the shared pet tree.
  A fighting guardian may survive its owner's death until its engagement ends.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Guardian
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects

  def tree do
    BT.selector([BT.action(&lifetime/3), Pet.tree()])
  end

  def lifetime(%Mob{internal: %{guardian: %Guardian{}}} = state, blackboard, %Context{now: now} = context) do
    cond do
      not owner_present?(state, context) ->
        {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}

      Core.dead?(state) ->
        {{:running, 500}, state, blackboard}

      expired?(state.internal.guardian.expires_at, now) ->
        {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}

      true ->
        {:failure, state, blackboard}
    end
  end

  defp owner_present?(%Mob{internal: %{pet: %{owner_guid: owner}, world: world}} = state, %Context{
         perception: perception
       }) do
    with %{alive?: alive?} <- Perception.metadata(perception, owner),
         {^world, _, _, _} <- Perception.position(perception, owner),
         distance when is_number(distance) and distance <= 120.0 <- Perception.distance(perception, owner) do
      alive? or state.internal.in_combat == true or Core.dead?(state)
    else
      _ -> false
    end
  end

  defp expired?(deadline, now), do: is_integer(deadline) and now >= deadline
end
