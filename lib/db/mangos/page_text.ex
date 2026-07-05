defmodule ThistleTea.DB.Mangos.PageText do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "page_text" do
    field(:text, :string)
    field(:next_page, :integer, default: 0)
  end
end
