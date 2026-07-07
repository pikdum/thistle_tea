defmodule Talent do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "Talent" do
    field(:tab, :integer)
    field(:tier, :integer)
    field(:column_index, :integer)
    field(:spell_rank_0, :integer)
    field(:spell_rank_1, :integer)
    field(:spell_rank_2, :integer)
    field(:spell_rank_3, :integer)
    field(:spell_rank_4, :integer)
  end
end
