defmodule ThistleTea.DB.Mangos.CreatureTemplateAddon do
  @moduledoc false
  use Ecto.Schema

  alias ThistleTea.DB.Mangos.AddonAuras

  @primary_key {:entry, :integer, autogenerate: false}
  schema "creature_template_addon" do
    field(:auras, :string)
  end

  def aura_ids(%__MODULE__{auras: auras}), do: AddonAuras.parse(auras)
  def aura_ids(_row), do: []
end
