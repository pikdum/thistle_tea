defmodule ThistleTea.DB.Mangos.BroadcastText do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "broadcast_text" do
    field(:male_text, :string, default: "")
    field(:female_text, :string, default: "")
    field(:chat_type, :integer, default: 0)
    field(:sound_id, :integer, default: 0)
    field(:language_id, :integer, default: 0)
    field(:emote_id1, :integer, default: 0)
    field(:emote_id2, :integer, default: 0)
    field(:emote_id3, :integer, default: 0)
    field(:emote_delay1, :integer, default: 0)
    field(:emote_delay2, :integer, default: 0)
    field(:emote_delay3, :integer, default: 0)
  end
end
