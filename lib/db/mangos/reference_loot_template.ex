defmodule ThistleTea.DB.Mangos.ReferenceLootTemplate do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false

  schema "reference_loot_template" do
    field(:entry, :integer)
    field(:item, :integer)
    field(:chance, :float, source: :ChanceOrQuestChance, default: 100.0)
    field(:groupid, :integer, default: 0)
    field(:mincount_or_ref, :integer, source: :mincountOrRef, default: 1)
    field(:maxcount, :integer, default: 1)
    field(:condition_id, :integer, default: 0)
  end

  def query(entry) do
    from(rlt in Mangos.ReferenceLootTemplate, where: rlt.entry == ^entry)
  end
end
