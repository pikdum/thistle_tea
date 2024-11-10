defmodule GossipMenuOption do
  use Ecto.Schema

  @primary_key false
  schema "gossip_menu_option" do
    field(:menu_id, :integer, primary_key: true, default: 0)
    field(:id, :integer, primary_key: true, default: 0)
    field(:option_icon, :integer, default: 0)
    field(:option_text, :string)
    field(:option_id, :integer, default: 0)
    field(:npc_option_npcflag, :integer, default: 0)
    field(:action_menu_id, :integer, default: 0)
    field(:action_poi_id, :integer, default: 0)
    field(:action_script_id, :integer, default: 0)
    field(:box_coded, :integer, default: 0)
    field(:box_money, :integer, default: 0)
    field(:box_text, :string)
    field(:condition_id, :integer, default: 0)
  end
end
