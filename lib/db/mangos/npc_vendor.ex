defmodule ThistleTea.DB.Mangos.NpcVendor do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false

  schema "npc_vendor" do
    field(:entry, :integer)
    field(:item, :integer)
    field(:maxcount, :integer, default: 0)
    field(:incrtime, :integer, default: 0)
    field(:condition_id, :integer, default: 0)
  end

  def query(entry) do
    from(nv in Mangos.NpcVendor, where: nv.entry == ^entry, order_by: nv.item)
  end
end
