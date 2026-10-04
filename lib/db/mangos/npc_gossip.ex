defmodule ThistleTea.DB.Mangos.NpcGossip do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:npc_guid, :integer, autogenerate: false}
  schema "npc_gossip" do
    field(:text_id, :integer, source: :textid)
  end
end
