defmodule ThistleTea.DB.Mangos.MailLootTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "mail_loot_template" do
    field(:entry, :integer)
    field(:item, :integer)
    field(:min_count, :integer, source: :mincountOrRef, default: 1)
    field(:max_count, :integer, source: :maxcount, default: 1)
  end
end
