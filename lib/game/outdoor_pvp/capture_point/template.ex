defmodule ThistleTea.Game.OutdoorPvp.CapturePoint.Template do
  @moduledoc "Capture-point timing, radius, and client slider fields from a game-object template."

  alias ThistleTea.Game.Entity.Data.GameObjectTemplate

  @enforce_keys [
    :entry,
    :radius,
    :display_state,
    :position_state,
    :neutral_state,
    :neutral_percent,
    :min_time,
    :max_time
  ]
  defstruct @enforce_keys

  def from_game_object(%GameObjectTemplate{entry: entry, type: 29, data: data}) do
    radius = Enum.at(data, 0, 0)
    maximum = Enum.at(data, 17, 0)

    if radius > 0 and maximum > 0 do
      %__MODULE__{
        entry: entry,
        radius: radius,
        display_state: Enum.at(data, 2, 0),
        position_state: Enum.at(data, 3, 0),
        neutral_state: Enum.at(data, 13, 0),
        neutral_percent: data |> Enum.at(12, 0) |> max(0) |> min(100),
        min_time: positive_time(Enum.at(data, 16, 0)),
        max_time: maximum
      }
    end
  end

  def from_game_object(_template), do: nil

  defp positive_time(seconds) when seconds > 0, do: seconds
  defp positive_time(_seconds), do: 60
end
