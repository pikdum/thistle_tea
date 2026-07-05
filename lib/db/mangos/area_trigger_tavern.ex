defmodule ThistleTea.DB.Mangos.AreaTriggerTavern do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "areatrigger_tavern" do
    field(:name, :string)
    field(:patch_min, :integer)
  end
end
