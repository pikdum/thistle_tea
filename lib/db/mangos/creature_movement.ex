defmodule CreatureMovement do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "creature_movement" do
    field(:point, :integer)
    field(:position_x, :float, default: 0.0)
    field(:position_y, :float, default: 0.0)
    field(:position_z, :float, default: 0.0)
    field(:waittime, :integer, default: 0)
    field(:script_id, :integer, default: 0)
    field(:textid1, :integer, default: 0)
    field(:textid2, :integer, default: 0)
    field(:textid3, :integer, default: 0)
    field(:textid4, :integer, default: 0)
    field(:textid5, :integer, default: 0)
    field(:emote, :integer, default: 0)
    field(:spell, :integer, default: 0)
    field(:orientation, :float, default: 0.0)
    field(:model1, :integer, default: 0)
    field(:model2, :integer, default: 0)

    # belongs_to(:creature, Creature, foreign_key: :id, references: :guid, define_field: false)
  end
end
