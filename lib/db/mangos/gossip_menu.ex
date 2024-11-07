defmodule GossipMenu do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}

  schema "gossip_menu" do
    field(:text_id, :integer, default: 0)
    field(:script_id, :integer, default: 0)
    field(:condition_id, :integer, default: 0)

    # TODO: is this 1:1 or 1:many?
    has_one(:npc_text, NpcText, foreign_key: :id, references: :text_id)
  end
end
