defmodule ThistleTea.DB.Mangos.NpcVendorTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "npc_vendor_template" do
    field(:entry, :integer)
    field(:slot, :integer, default: 0)
    field(:item, :integer)
    field(:maxcount, :integer, default: 0)
    field(:incrtime, :integer, default: 0)
    field(:itemflags, :integer, default: 0)
    field(:condition_id, :integer, default: 0)
  end
end
