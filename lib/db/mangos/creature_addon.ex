defmodule ThistleTea.DB.Mangos.CreatureAddon do
  @moduledoc false
  use Ecto.Schema

  alias ThistleTea.DB.Mangos.AddonAuras

  @primary_key {:guid, :integer, autogenerate: false}
  schema "creature_addon" do
    field(:display_id, :integer, default: 0)
    field(:mount_display_id, :integer, default: -1)
    field(:equipment_id, :integer, default: -1)
    field(:stand_state, :integer, default: 0)
    field(:sheath_state, :integer, default: 1)
    field(:emote_state, :integer, default: 0)
    field(:auras, :string)
  end

  def aura_ids(%__MODULE__{auras: auras}), do: AddonAuras.parse(auras)
  def aura_ids(_row), do: []
end
