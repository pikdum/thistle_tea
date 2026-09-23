defmodule ThistleTea.DB.Mangos.SpellScriptTarget do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_script_target" do
    field(:entry, :integer)
    field(:type, :integer)
    field(:target_entry, :integer, source: :targetEntry)
    field(:condition_id, :integer, source: :conditionId)
    field(:inverse_effect_mask, :integer, source: :inverseEffectMask)
    field(:build_min, :integer)
    field(:build_max, :integer)
  end
end
