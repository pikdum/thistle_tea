defmodule ThistleTea.DB.Mangos.GossipMenu do
  use Ecto.Schema

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "gossip_menu" do
    field(:entry, :integer, primary_key: true, default: 0)
    field(:text_id, :integer, primary_key: true, default: 0)
    field(:script_id, :integer, primary_key: true, default: 0)
    field(:condition_id, :integer, default: 0)

    has_one(:npc_text, Mangos.NpcText, foreign_key: :id, references: :text_id)

    has_many(:gossip_menu_option, Mangos.GossipMenuOption,
      foreign_key: :menu_id,
      references: :entry
    )
  end
end
