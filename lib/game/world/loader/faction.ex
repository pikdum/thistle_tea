defmodule ThistleTea.Game.World.Loader.Faction do
  @moduledoc false

  alias ThistleTea.DBC

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def metadata(faction_template_id) when is_integer(faction_template_id) and faction_template_id > 0 do
    case :ets.lookup(__MODULE__, faction_template_id) do
      [{^faction_template_id, metadata}] -> metadata
      [] -> load_metadata(faction_template_id)
    end
  end

  def metadata(_faction_template_id) do
    %{
      faction_template_id: nil,
      faction_template: nil,
      faction_can_have_reputation?: false
    }
  end

  defp load_metadata(faction_template_id) do
    faction_template = DBC.get(FactionTemplate, faction_template_id)

    metadata = %{
      faction_template_id: faction_template_id,
      faction_template: faction_template,
      faction_can_have_reputation?: faction_can_have_reputation?(faction_template)
    }

    :ets.insert(__MODULE__, {faction_template_id, metadata})
    metadata
  end

  defp faction_can_have_reputation?(%FactionTemplate{faction: faction_id})
       when is_integer(faction_id) and faction_id > 0 do
    faction_id
    |> then(&DBC.get(Faction, &1))
    |> Faction.can_have_reputation?()
  end

  defp faction_can_have_reputation?(_faction_template), do: false
end
