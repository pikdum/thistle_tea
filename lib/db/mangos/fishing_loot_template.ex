defmodule ThistleTea.DB.Mangos.FishingLootTemplate do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false

  schema "fishing_loot_template" do
    field(:entry, :integer)
    field(:item, :integer)
    field(:chance, :float, source: :ChanceOrQuestChance, default: 100.0)
    field(:groupid, :integer, default: 0)
    field(:mincount_or_ref, :integer, source: :mincountOrRef, default: 1)
    field(:maxcount, :integer, default: 1)
    field(:condition_id, :integer, default: 0)
  end

  def query(entry) do
    from(flt in Mangos.FishingLootTemplate, where: flt.entry == ^entry)
  end
end
