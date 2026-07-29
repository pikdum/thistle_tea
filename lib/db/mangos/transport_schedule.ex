defmodule ThistleTea.DB.Mangos.TransportSchedule do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "transports" do
    field(:entry, :integer, primary_key: true)
    field(:build, :integer, primary_key: true)
    field(:name, :string)
    field(:period, :integer)
  end
end
