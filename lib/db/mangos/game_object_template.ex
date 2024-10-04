defmodule GameObjectTemplate do
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "gameobject_template" do
    field(:type, :integer, default: 0)
    field(:display_id, :integer, source: :displayId, default: 0)
    field(:name, :string, default: "")
    field(:faction, :integer, default: 0)
    field(:flags, :integer, default: 0)
    field(:size, :float, default: 1.0)
    field(:data0, :integer, default: 0)
    field(:data1, :integer, default: 0)
    field(:data2, :integer, default: 0)
    field(:data3, :integer, default: 0)
    field(:data4, :integer, default: 0)
    field(:data5, :integer, default: 0)
    field(:data6, :integer, default: 0)
    field(:data7, :integer, default: 0)
    field(:data8, :integer, default: 0)
    field(:data9, :integer, default: 0)
    field(:data10, :integer, default: 0)
    field(:data11, :integer, default: 0)
    field(:data12, :integer, default: 0)
    field(:data13, :integer, default: 0)
    field(:data14, :integer, default: 0)
    field(:data15, :integer, default: 0)
    field(:data16, :integer, default: 0)
    field(:data17, :integer, default: 0)
    field(:data18, :integer, default: 0)
    field(:data19, :integer, default: 0)
    field(:data20, :integer, default: 0)
    field(:data21, :integer, default: 0)
    field(:data22, :integer, default: 0)
    field(:data23, :integer, default: 0)
    field(:mingold, :integer, default: 0)
    field(:maxgold, :integer, default: 0)
  end
end
