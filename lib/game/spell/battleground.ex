defmodule ThistleTea.Game.Spell.Battleground do
  @moduledoc "Pure admission rules for battleground-only spells and Alterac Valley standards."

  alias ThistleTea.Game.Spell

  @alterac_spells [22_563, 22_564, 23_538, 23_539]

  def restricted?(%Spell{} = spell), do: spell.id in @alterac_spells or Spell.attribute?(spell, :only_battlegrounds)

  def validate(%Spell{id: id}, context) when id in @alterac_spells do
    case context do
      %{map_id: 30, phase: :active} -> :ok
      %{map_id: 30, phase: {:ended, _winner}} -> :ok
      _outside -> {:error, :requires_area}
    end
  end

  def validate(%Spell{} = spell, context) do
    if Spell.attribute?(spell, :only_battlegrounds) and is_nil(context),
      do: {:error, :only_battlegrounds},
      else: :ok
  end
end
