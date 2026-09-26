defmodule ThistleTea.Game.Entity.Logic.Aura.HealingPower do
  @moduledoc """
  Selects Holy Power and Totemic Power buffs from the healed recipient's class.
  Proc eligibility and chance are handled by the shared aura reaction path.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @buffs %{
    28_789 => %{mana: 28_795, spell: 28_793, attack: 28_791, armor: 28_790},
    28_823 => %{mana: 28_824, spell: 28_825, attack: 28_826, armor: 28_827}
  }

  def supported?(%Spell{id: id}), do: is_map_key(@buffs, id)
  def supported?(_spell), do: false

  def events(%Holder{spell: %Spell{id: id}} = holder, owner_guid, %{
        victim_guid: victim,
        victim_alive?: true,
        victim_class: class
      })
      when is_map_key(@buffs, id) and is_integer(victim) do
    case buff_type(class) do
      nil ->
        []

      type ->
        [
          Effects.trigger_spell(owner_guid, holder.caster_level || 1, victim, Map.fetch!(@buffs[id], type),
            cast_item_guid: holder.cast_item_guid,
            triggered_by_spell_id: id,
            requires_living_target?: true
          )
        ]
    end
  end

  def events(_holder, _owner_guid, _context), do: []

  defp buff_type(class) when class in [2, 5, 7, 11], do: :mana
  defp buff_type(class) when class in [8, 9], do: :spell
  defp buff_type(class) when class in [3, 4], do: :attack
  defp buff_type(1), do: :armor
  defp buff_type(_class), do: nil
end
