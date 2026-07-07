defmodule TalentTab do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "TalentTab" do
    field(:name_en_gb, :string)
    field(:race_mask, :integer)
    field(:class_mask, :integer)
    field(:order_index, :integer)
  end
end
