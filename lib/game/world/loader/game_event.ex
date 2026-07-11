defmodule ThistleTea.Game.World.Loader.GameEvent do
  @moduledoc """
  Loads schedulable VMangos game events into the runtime schedule model.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.System.GameEvent.Schedule
  alias ThistleTea.Game.World.System.GameEvent.Schedule.Entry

  @supported_patch 10

  def load_schedule do
    Mangos.GameEvent
    |> where([event], event.disabled == 0)
    |> where([event], event.hardcoded == 0)
    |> where([event], event.patch_min <= @supported_patch and event.patch_max >= @supported_patch)
    |> where([event], fragment("? != '0000-00-00 00:00:00'", event.start_time))
    |> where([event], fragment("? != '0000-00-00 00:00:00'", event.end_time))
    |> order_by([event], event.entry)
    |> Mangos.Repo.all()
    |> from_rows()
  end

  def from_rows(rows) when is_list(rows) do
    rows
    |> Enum.map(&from_row/1)
    |> Schedule.new()
  end

  defp from_row(%Mangos.GameEvent{} = row) do
    %Entry{
      id: row.entry,
      starts_at: DateTime.from_naive!(row.start_time, "Etc/UTC"),
      ends_at: DateTime.from_naive!(row.end_time, "Etc/UTC"),
      occurrence_seconds: row.occurrence * 60,
      length_seconds: row.length * 60,
      description: row.description || ""
    }
  end
end
