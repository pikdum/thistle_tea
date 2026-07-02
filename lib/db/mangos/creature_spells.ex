defmodule ThistleTea.DB.Mangos.CreatureSpells do
  @moduledoc false
  use Ecto.Schema

  @slots 1..8

  @primary_key {:entry, :integer, autogenerate: false}
  schema "creature_spells" do
    field(:name, :string)

    for slot <- @slots do
      field(:"spellId_#{slot}", :integer)
      field(:"probability_#{slot}", :integer)
      field(:"castTarget_#{slot}", :integer)
      field(:"targetParam1_#{slot}", :integer)
      field(:"targetParam2_#{slot}", :integer)
      field(:"castFlags_#{slot}", :integer)
      field(:"delayInitialMin_#{slot}", :integer)
      field(:"delayInitialMax_#{slot}", :integer)
      field(:"delayRepeatMin_#{slot}", :integer)
      field(:"delayRepeatMax_#{slot}", :integer)
    end
  end

  def slots(%__MODULE__{} = row) do
    for slot <- @slots,
        spell_id = Map.get(row, :"spellId_#{slot}"),
        is_integer(spell_id) and spell_id > 0 do
      %{
        spell_id: spell_id,
        probability: Map.get(row, :"probability_#{slot}"),
        cast_target: Map.get(row, :"castTarget_#{slot}"),
        target_param1: Map.get(row, :"targetParam1_#{slot}"),
        target_param2: Map.get(row, :"targetParam2_#{slot}"),
        cast_flags: Map.get(row, :"castFlags_#{slot}"),
        delay_initial_min: Map.get(row, :"delayInitialMin_#{slot}"),
        delay_initial_max: Map.get(row, :"delayInitialMax_#{slot}"),
        delay_repeat_min: Map.get(row, :"delayRepeatMin_#{slot}"),
        delay_repeat_max: Map.get(row, :"delayRepeatMax_#{slot}")
      }
    end
  end

  def slots(_row), do: []
end
