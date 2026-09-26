defmodule ThistleTea.Game.Entity.Logic.Aura.ProcEquipment do
  @moduledoc "Checks outgoing aura procs against the player's current usable equipment."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Spell

  def allowed?(%Character{} = character, %Spell{} = spell, context) do
    Spell.attribute?(spell, :no_proc_equip_requirement) or equipped?(character, spell, context)
  end

  def allowed?(_entity, _spell, _context), do: true

  defp equipped?(character, %Spell{equipped_item_class: 2} = spell, context) do
    case CombatWeapon.usable(character, hand(context)) do
      %{class: 2, subclass: subclass} -> matches_subclass?(spell, subclass)
      _weapon -> false
    end
  end

  defp equipped?(%Character{unit: unit, player: player}, %Spell{equipped_item_class: 4} = spell, _context) do
    :offhand not in (player.broken_equipment || []) and
      Map.get(unit.equipment_bonuses || %{}, :shields, 0) > 0 and matches_subclass?(spell, 6)
  end

  defp equipped?(_character, _spell, _context), do: true

  defp hand(%{hand: hand}) when hand in [:mainhand, :offhand, :ranged], do: hand
  defp hand(%{attack_hand: hand}) when hand in [:mainhand, :offhand, :ranged], do: hand
  defp hand(%{spell: %Spell{} = spell}), do: if(Spell.ranged_attack?(spell), do: :ranged, else: :mainhand)
  defp hand(_context), do: :mainhand

  defp matches_subclass?(%Spell{equipped_item_subclass_mask: mask}, subclass)
       when is_integer(mask) and is_integer(subclass) and subclass >= 0 do
    Bitwise.band(mask, Bitwise.bsl(1, subclass)) != 0
  end

  defp matches_subclass?(_spell, _subclass), do: false
end
