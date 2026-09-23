defmodule ThistleTea.DB.Mangos.SpellMod do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_mod" do
    field(:id, :integer, source: :Id)
    field(:aura_interrupt_flags, :integer, source: :AuraInterruptFlags)
  end
end
