defmodule ThistleTea.Game.Entity.Logic.AI.BT.MiniPet do
  @moduledoc """
  Passive critter following with owner, world, and distance lifetime checks.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects

  def tree, do: BT.action(&tick/3)

  def tick(
        %Mob{internal: %{pet: %{owner_guid: owner}, world: world}} = state,
        blackboard,
        %Context{perception: perception} = context
      ) do
    with %{alive?: true} <- Perception.metadata(perception, owner),
         {^world, _, _, _} <- Perception.position(perception, owner),
         distance when is_number(distance) and distance <= 120.0 <- Perception.distance(perception, owner) do
      if Core.dead?(state) do
        {{:running, 500}, state, blackboard}
      else
        {state, blackboard} = EventAI.tick(state, blackboard, context.now, context)
        follow_command(state, blackboard, context)
      end
    else
      _ -> {:success, Effects.enqueue(state, Effects.despawn_self(0, 0)), blackboard}
    end
  end

  defp follow_command(%Mob{internal: %{pet: %{command_state: :follow}}} = state, blackboard, context) do
    Pet.follow_owner(state, blackboard, context)
  end

  defp follow_command(state, blackboard, _context), do: {{:running, 500}, state, blackboard}
end
