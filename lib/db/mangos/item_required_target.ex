defmodule ThistleTea.DB.Mangos.ItemRequiredTarget do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "item_required_target" do
    field(:entry, :integer)
    field(:type, :integer)
    field(:target_entry, :integer)
  end
end
