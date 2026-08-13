defmodule ThistleTea.DB.Mangos.BattlemasterEntry do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "battlemaster_entry" do
    field(:bg_template, :integer)
  end
end
