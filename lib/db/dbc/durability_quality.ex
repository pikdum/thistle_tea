defmodule DurabilityQuality do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "DurabilityQuality" do
    field(:data, :float)
  end
end
