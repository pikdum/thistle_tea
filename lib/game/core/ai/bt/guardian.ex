defmodule ThistleTea.Game.Core.AI.BT.Guardian do
  @moduledoc """
  Guardian lifetime around the shared pet tree.
  A fighting guardian may survive its owner's death until its engagement ends.
  """

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Pet
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal.Guardian
  alias ThistleTea.Game.Core.Entity.Mob

  def tree do
    BT.selector([BT.action(&lifetime/3), Pet.tree()])
  end

  def lifetime(%Mob{internal: %{guardian: %Guardian{}}} = state, blackboard, %Context{now: now} = context) do
    cond do
      not owner_present?(state, context) ->
        {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}

      Entity.dead?(state) ->
        {{:running, 500}, state, blackboard}

      blackboard.guardian.expired? ->
        {{:running, 500}, state, blackboard}

      expired?(state.internal.guardian.expires_at, now) ->
        blackboard = %{blackboard | guardian: %{blackboard.guardian | expired?: true}}
        {:success, Effects.enqueue(state, expiration_effect(state)), blackboard}

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
      alive? or state.internal.in_combat == true or Entity.dead?(state)
    else
      _ -> false
    end
  end

  defp expired?(deadline, now), do: is_integer(deadline) and now >= deadline

  defp expiration_effect(%Mob{internal: %{guardian: %Guardian{expiration_spell_id: id}}} = state) when is_integer(id) do
    Effects.trigger_spell(state.object.guid, state.unit.level, state.object.guid, id, resolve_targets?: true)
  end

  defp expiration_effect(_state), do: Effects.despawn_self(0, 0)
end
