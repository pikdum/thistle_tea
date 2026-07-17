defmodule ThistleTea.DB.Mangos.SpellProcEvent do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "spell_proc_event" do
    field(:entry, :integer)
    field(:school_mask, :integer, source: :SchoolMask)
    field(:spell_family, :integer, source: :SpellFamilyName)
    field(:family_mask_0, :integer, source: :SpellFamilyMask0)
    field(:family_mask_1, :integer, source: :SpellFamilyMask1)
    field(:family_mask_2, :integer, source: :SpellFamilyMask2)
    field(:proc_flags, :integer, source: :procFlags)
    field(:proc_ex, :integer, source: :procEx)
    field(:ppm_rate, :float, source: :ppmRate)
    field(:custom_chance, :float, source: :CustomChance)
    field(:cooldown_ms, :integer, source: :Cooldown)
    field(:build_min, :integer)
    field(:build_max, :integer)
  end
end
