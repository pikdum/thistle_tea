defmodule ThistleTea.Game.Core.Battleground.Entrance do
  @moduledoc """
  A battleground's portal in the world (`areatrigger_bg_entrance`). Walking
  into it shows the battleground list to a player of its team within the
  battleground's levels, and the player returns outside it, at its exit.
  """

  alias ThistleTea.Game.Core.Battleground.Template

  defstruct [:trigger_id, :team, :type_id, :exit_map, :exit_position]

  @alliance 469
  @horde 67

  def from_row(%{id: id, team: team, bg_template: type_id} = row) do
    %__MODULE__{
      trigger_id: id,
      team: team(team),
      type_id: type_id,
      exit_map: row.exit_map,
      exit_position: {row.exit_position_x, row.exit_position_y, row.exit_position_z, row.exit_orientation}
    }
  end

  def admit(%__MODULE__{team: team}, %Template{min_level: min, max_level: max}, team, level)
      when is_integer(level) and level >= min and level <= max, do: :ok

  def admit(%__MODULE__{team: team}, %Template{min_level: min}, _team, _level),
    do: {:error, "You must be in the #{team_name(team)} and at least #{ordinal(min)} level to enter."}

  defp team(@alliance), do: :alliance
  defp team(@horde), do: :horde
  defp team(_faction), do: nil

  defp team_name(:alliance), do: "Alliance"
  defp team_name(:horde), do: "Horde"

  defp ordinal(number) when rem(number, 100) in 11..13, do: "#{number}th"
  defp ordinal(number) when rem(number, 10) == 1, do: "#{number}st"
  defp ordinal(number) when rem(number, 10) == 2, do: "#{number}nd"
  defp ordinal(number) when rem(number, 10) == 3, do: "#{number}rd"
  defp ordinal(number), do: "#{number}th"
end
