defmodule ThistleTea.Game.World.HonorStore do
  @moduledoc """
  Runtime honor records retained across coordinator restarts. The application
  owns the table; the honor coordinator is its only writer.
  """

  alias ThistleTea.Game.Entity.Data.Honor.Entry
  alias ThistleTea.Game.Entity.Logic.Honor.Ledger

  def init do
    :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])
  end

  def load(day, weekday, table \\ __MODULE__) do
    case :ets.lookup(table, :calendar) do
      [{:calendar, stored_day, week_start}] ->
        entries = for {guid, %Entry{} = entry} <- :ets.tab2list(table), into: %{}, do: {guid, entry}
        %Ledger{day: stored_day, week_start: week_start, entries: entries}

      [] ->
        Ledger.new(day, weekday)
    end
  end

  def save(%Ledger{} = ledger, guids, table \\ __MODULE__) do
    entries = Enum.map(guids, &{&1, Map.fetch!(ledger.entries, &1)})
    :ets.insert(table, [{:calendar, ledger.day, ledger.week_start} | entries])
    :ok
  end
end
