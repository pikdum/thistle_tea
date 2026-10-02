defmodule ThistleTea.DB.Mangos.CreatureCharmSpell do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "creature_charm_spells" do
    field(:entry, :integer)
    field(:slot, :integer)
    field(:availability, :float, default: 100.0)
    field(:spell_id, :integer)
    field(:cooldown_min, :integer, default: 0)
    field(:cooldown_max, :integer, default: 0)
    field(:patch_min, :integer, default: 0)
    field(:patch_max, :integer, default: 10)
  end
end
