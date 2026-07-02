defmodule ThistleTea.DB.Mangos.CreatureEquipTemplate do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "creature_equip_template" do
    field(:entry, :integer)
    field(:probability, :integer, default: 1)
    field(:item1, :integer, default: 0)
    field(:item2, :integer, default: 0)
    field(:item3, :integer, default: 0)
  end

  def query(entry) do
    from(cet in Mangos.CreatureEquipTemplate, where: cet.entry == ^entry)
  end
end
