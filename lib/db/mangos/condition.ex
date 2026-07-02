defmodule ThistleTea.DB.Mangos.Condition do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  @primary_key {:condition_entry, :integer, autogenerate: false}
  schema "conditions" do
    field(:type, :integer, default: 0)
    field(:value1, :integer, default: 0)
    field(:value2, :integer, default: 0)
    field(:value3, :integer, default: 0)
    field(:value4, :integer, default: 0)
    field(:flags, :integer, default: 0)
  end

  def query(entries) when is_list(entries) do
    from(c in __MODULE__, where: c.condition_entry in ^entries)
  end
end
