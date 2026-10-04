defmodule ThistleTea.DB.Mangos.ForbiddenItem do
  @moduledoc """
  vmangos `forbidden_items`: items removed by a patch (`after_or_before` 0)
  or not yet added before one (`after_or_before` 1), which loaders keep off
  vendors and out of loot for that patch.
  """
  use Ecto.Schema

  import Ecto.Query

  @primary_key false
  schema "forbidden_items" do
    field(:entry, :integer, primary_key: true)
    field(:patch, :integer)
    field(:after_or_before, :integer, primary_key: true)
  end

  def entries(patch) when is_integer(patch) do
    from(f in __MODULE__,
      where: (f.after_or_before == 0 and f.patch <= ^patch) or (f.after_or_before == 1 and f.patch >= ^patch),
      select: f.entry
    )
  end
end
