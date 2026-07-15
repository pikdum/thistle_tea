defmodule ThistleTea.Game.World.Loader.Mail do
  @moduledoc """
  Boot-loaded cache of DBC mail text and VMangos mail-template attachments.
  Gameplay mail producers read this cache rather than querying either seed
  database.
  """

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.DBC.MailTemplate
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    attachments =
      Mangos.MailLootTemplate
      |> Mangos.Repo.all()
      |> Map.new(fn row ->
        ItemLoader.get_template(row.item)
        {row.entry, %{item: row.item, min_count: row.min_count, max_count: row.max_count}}
      end)

    MailTemplate
    |> DBC.all()
    |> Enum.each(fn template ->
      value = %{body: template.body || "", attachment: Map.get(attachments, template.id)}
      :ets.insert(__MODULE__, {template.id, value})
    end)

    :ok
  end

  def get(template_id) when is_integer(template_id) and template_id > 0 do
    case :ets.lookup(__MODULE__, template_id) do
      [{^template_id, template}] -> template
      _ -> nil
    end
  end

  def get(_template_id), do: nil
end
