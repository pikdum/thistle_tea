defmodule ThistleTea.DB.Mangos.CreatureLinkingTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "creature_linking_template" do
    field(:entry, :integer, primary_key: true)
    field(:map, :integer, primary_key: true)
    field(:master_entry, :integer)
    field(:flag, :integer)
    field(:search_range, :integer)
  end
end
