defmodule ThistleTea.DB.Mangos.GameEvent do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "game_event" do
    field(:start_time, :naive_datetime)
    field(:end_time, :naive_datetime)
    field(:occurrence, :integer, source: :occurence)
    field(:length, :integer)
    field(:holiday, :integer)
    field(:description, :string)
    field(:hardcoded, :integer)
    field(:disabled, :integer)
    field(:patch_min, :integer)
    field(:patch_max, :integer)
  end
end
