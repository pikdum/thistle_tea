defmodule ThistleTea.Game.World.Entity.Player.ObjectRequirement do
  @moduledoc """
  Whether a game object's `gameobject_requirement` lets a player use it, read
  from the required spawn's published metadata in the same world copy.
  """

  alias ThistleTea.Game.Core.GameObject.UseRequirement
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectRequirement, as: GameObjectRequirementLoader
  alias ThistleTea.Game.World.Metadata

  def met?(world, guid, requirements \\ &GameObjectRequirementLoader.get/1) do
    with %{db_guid: db_guid} when is_integer(db_guid) <- Metadata.query(guid, [:db_guid]),
         %UseRequirement{} = requirement <- requirements.(db_guid) do
      UseRequirement.met?(requirement, required_state(world, requirement))
    else
      _ungated -> true
    end
  end

  defp required_state(world, %UseRequirement{type: :dead_creature, db_guid: db_guid}) do
    with guid when is_integer(guid) <- World.spawn_guid(world, :mob, db_guid), do: Metadata.query(guid, [:alive?])
  end

  defp required_state(world, %UseRequirement{type: :active_object, db_guid: db_guid}) do
    with guid when is_integer(guid) <- World.spawn_guid(world, :game_object, db_guid),
         do: Metadata.query(guid, [:go_state])
  end
end
