defmodule ThistleTea.Game.Entity.Server.AIEnvironment do
  @moduledoc """
  Builds the world, navigation, time, and randomness environment consumed by
  one entity behavior-tree tick.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  def context(entity, now \\ Time.now()) when is_integer(now) do
    %Context{
      now: now,
      perception: perception(entity, now),
      random: random(),
      navigation: navigation()
    }
  end

  def move_to(entity, destination, opts \\ [], now \\ Time.now()) do
    case Navigation.move_to(context(entity, now), entity, destination, opts) do
      {:ok, entity} -> entity
      {:error, :no_path, entity} -> entity
    end
  end

  defp perception(entity, now) do
    %Perception{
      position: &World.position(&1, now),
      grounded_position: &World.grounded_target_position(&1, now),
      projected_position: &World.projected_position(&1, &2, now),
      distance: &distance(entity, &1, now),
      moving?: &World.moving?(&1, now),
      metadata: &Metadata.get/1,
      nearby: &nearby(entity, &1, &2),
      line_of_sight?: &World.line_of_sight?(entity, &1)
    }
  end

  defp nearby(entity, :mobs, radius), do: World.nearby_mobs(entity, radius)
  defp nearby(entity, :players, radius), do: World.nearby_players(entity, radius)
  defp nearby(_entity, _kind, _radius), do: []

  defp distance(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}, guid, now) do
    case World.position(guid, now) do
      {^world, tx, ty, tz} ->
        :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))

      _ ->
        nil
    end
  end

  defp distance(_entity, _guid, _now), do: nil

  defp random do
    %Random{
      float: &:rand.uniform/0,
      integer: &:rand.uniform/1
    }
  end

  defp navigation do
    %Navigation{
      find_path: &Pathfinding.find_path/3,
      find_random_point: &Pathfinding.find_random_point_around_circle/3
    }
  end
end
