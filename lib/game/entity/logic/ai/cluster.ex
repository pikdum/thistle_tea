defmodule ThistleTea.Game.Entity.Logic.AI.Cluster do
  @moduledoc """
  Pure angular-slot selection for melee attackers converging on a shared
  target. Mirrors MaNGOS's `ObjectPosSelector`: given a desired approach
  direction and the angular sectors already occupied by other nearby units,
  pick the angle closest to the desired one that does not overlap any sector,
  so attackers fan out around the target instead of stacking.
  """
  @epsilon 1.0e-4

  def free_angle(base_angle, occupied) when is_number(base_angle) and is_list(occupied) do
    if clear?(base_angle, occupied) do
      base_angle
    else
      occupied
      |> candidate_angles()
      |> Enum.filter(&clear?(&1, occupied))
      |> Enum.min_by(&angular_distance(&1, base_angle), fn -> base_angle end)
    end
  end

  defp candidate_angles(occupied) do
    Enum.flat_map(occupied, fn {angle, clearance} ->
      [angle - clearance - @epsilon, angle + clearance + @epsilon]
    end)
  end

  defp clear?(angle, occupied) do
    Enum.all?(occupied, fn {center, clearance} ->
      angular_distance(angle, center) >= clearance - @epsilon
    end)
  end

  defp angular_distance(a, b) do
    abs(:math.atan2(:math.sin(a - b), :math.cos(a - b)))
  end
end
