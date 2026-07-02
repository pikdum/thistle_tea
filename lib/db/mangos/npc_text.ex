defmodule ThistleTea.DB.Mangos.NpcText do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false, source: :ID}
  schema "npc_text" do
    field(:broadcast_text_id0, :integer, source: :BroadcastTextID0, default: 0)
    field(:prob0, :float, source: :Probability0, default: 0.0)
    field(:broadcast_text_id1, :integer, source: :BroadcastTextID1, default: 0)
    field(:prob1, :float, source: :Probability1, default: 0.0)
    field(:broadcast_text_id2, :integer, source: :BroadcastTextID2, default: 0)
    field(:prob2, :float, source: :Probability2, default: 0.0)
    field(:broadcast_text_id3, :integer, source: :BroadcastTextID3, default: 0)
    field(:prob3, :float, source: :Probability3, default: 0.0)
    field(:broadcast_text_id4, :integer, source: :BroadcastTextID4, default: 0)
    field(:prob4, :float, source: :Probability4, default: 0.0)
    field(:broadcast_text_id5, :integer, source: :BroadcastTextID5, default: 0)
    field(:prob5, :float, source: :Probability5, default: 0.0)
    field(:broadcast_text_id6, :integer, source: :BroadcastTextID6, default: 0)
    field(:prob6, :float, source: :Probability6, default: 0.0)
    field(:broadcast_text_id7, :integer, source: :BroadcastTextID7, default: 0)
    field(:prob7, :float, source: :Probability7, default: 0.0)
  end
end
