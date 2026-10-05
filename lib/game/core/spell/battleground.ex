defmodule ThistleTea.Game.Core.Spell.Battleground do
  @moduledoc "Pure admission rules for battleground-only spells and Alterac Valley standards."

  alias ThistleTea.Game.Core.Battleground.AlteracValley.Beacon
  alias ThistleTea.Game.Core.Spell

  @alterac_spells [22_563, 22_564, 23_538, 23_539]

  def restricted?(%Spell{} = spell),
    do:
      spell.id in @alterac_spells or Map.has_key?(Beacon.plant_spells(), spell.id) or
        Spell.attribute?(spell, :only_battlegrounds)

  def validate(%Spell{id: id}, context) when id in @alterac_spells do
    case context do
      %{map_id: 30, phase: :active} -> :ok
      %{map_id: 30, phase: {:ended, _winner}} -> :ok
      _outside -> {:error, :requires_area}
    end
  end

  def validate(%Spell{} = spell, context) do
    case Map.get(Beacon.plant_spells(), spell.id) do
      nil ->
        if Spell.attribute?(spell, :only_battlegrounds) and is_nil(context),
          do: {:error, :only_battlegrounds},
          else: :ok

      team ->
        case context do
          %{map_id: 30, phase: :active, team: ^team} -> :ok
          _ineligible -> {:error, :requires_area}
        end
    end
  end
end
