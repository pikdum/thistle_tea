defmodule ThistleTea.Game.World.Loader.GameEvent do
  @moduledoc """
  Loads schedulable VMangos game events into the runtime schedule model:
  dated recurring events, and the hardcoded events whose calendar a
  `Core.GameEvent.Rule` keeps. A hardcoded event loads even when its row is
  disabled, since its rule's driver decides whether it runs.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.GameEvent.Rule
  alias ThistleTea.Game.Core.GameEvent.Schedule
  alias ThistleTea.Game.Core.GameEvent.Schedule.Entry

  @supported_patch 10

  def load_schedule do
    from_rows(dated_rows() ++ hardcoded_rows())
  end

  def from_rows(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(&from_row/1)
    |> Schedule.new()
  end

  defp dated_rows do
    supported_rows()
    |> where([event], event.disabled == 0)
    |> where([event], event.hardcoded == 0)
    |> where([event], fragment("? != '0000-00-00 00:00:00'", event.start_time))
    |> where([event], fragment("? != '0000-00-00 00:00:00'", event.end_time))
    |> Mangos.Repo.all()
  end

  defp hardcoded_rows do
    supported_rows()
    |> where([event], event.hardcoded != 0 and event.entry in ^Rule.events())
    |> select([event], struct(event, [:entry, :description, :hardcoded]))
    |> Mangos.Repo.all()
  end

  defp supported_rows do
    Mangos.GameEvent
    |> where([event], event.patch_min <= @supported_patch and event.patch_max >= @supported_patch)
  end

  defp from_row(%Mangos.GameEvent{hardcoded: hardcoded} = row) when hardcoded not in [nil, 0] do
    case Rule.for_event(row.entry) do
      nil -> []
      rule -> [%Entry{id: row.entry, rule: rule, description: row.description || ""}]
    end
  end

  defp from_row(%Mangos.GameEvent{} = row) do
    [
      %Entry{
        id: row.entry,
        starts_at: DateTime.from_naive!(row.start_time, "Etc/UTC"),
        ends_at: DateTime.from_naive!(row.end_time, "Etc/UTC"),
        occurrence_seconds: row.occurrence * 60,
        length_seconds: row.length * 60,
        description: row.description || ""
      }
    ]
  end
end
