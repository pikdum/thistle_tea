defmodule ThistleTea.Game.Core.MeetingStone.Roles do
  @moduledoc "Class-based vanilla Meeting Stone roles and deterministic assignment of a party's occupied slots."

  @slots [:tank, :healer, :damage, :damage, :damage]

  def priority(class, :tank) when class == 1, do: 3
  def priority(class, :tank) when class in [2, 11], do: 2
  def priority(class, :healer) when class in [2, 5, 7, 11], do: 3
  def priority(class, :damage) when class in [3, 4, 8, 9], do: 3
  def priority(class, :damage) when class in [1, 2, 7, 11], do: 2
  def priority(5, :damage), do: 1
  def priority(_class, _role), do: 0

  def available(players) do
    {slots, _remaining} =
      Enum.reduce(@slots, {[], players}, fn role, {slots, remaining} ->
        candidate = Enum.max_by(remaining, &priority(&1.class, role), fn -> nil end)

        if candidate && priority(candidate.class, role) > 0 do
          {slots, List.delete(remaining, candidate)}
        else
          {slots ++ [role], remaining}
        end
      end)

    slots
  end
end
