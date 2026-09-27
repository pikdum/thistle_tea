defmodule ThistleTea.Game.Entity.Logic.AttackTimers do
  @moduledoc """
  Restarts attack deadlines after spell launches and combat equipment changes.
  Weapon replacement resets only the affected hand; aura speed changes leave
  the current swing intact and take effect when its next period starts.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Entity.Logic.Core

  def reset(%{internal: %Internal{} = internal} = entity, hand, now) when hand in [:mainhand, :offhand] do
    {key, period} =
      case hand do
        :mainhand -> {:next_attack_at, Combat.attack_speed_ms(entity)}
        :offhand -> {:next_offhand_attack_at, Combat.offhand_attack_speed_ms(entity) || 2_000}
      end

    blackboard = internal.blackboard |> Blackboard.ensure() |> Blackboard.put_next_at(key, period, now)
    %{entity | internal: %{internal | blackboard: blackboard}}
  end

  def reset(%Character{} = character, :ranged, now), do: AutoRepeat.reset_timer(character, now)

  def equipment_changed(%Character{internal: %{in_combat: true}} = character, %Character{} = previous, now) do
    if Core.dead?(character) do
      character
    else
      reset_changed_weapons(character, previous, now)
    end
  end

  def equipment_changed(%Character{} = character, %Character{}, _now), do: character

  defp reset_changed_weapons(character, previous, now) do
    Enum.reduce([:mainhand, :offhand, :ranged], character, fn hand, current ->
      if changed_weapon?(previous, character, hand),
        do: current |> reset(hand, now) |> Core.mark_broadcast_update(),
        else: current
    end)
  end

  defp changed_weapon?(previous, character, hand) do
    previous_weapon = usable_weapon(previous, hand)
    current_weapon = usable_weapon(character, hand)

    changed? =
      slot_guid(previous.player, hand) != slot_guid(character.player, hand) or
        is_nil(previous_weapon) != is_nil(current_weapon)

    changed? and (not is_nil(previous_weapon) or not is_nil(current_weapon))
  end

  defp slot_guid(%Player{mainhand: guid}, :mainhand), do: guid
  defp slot_guid(%Player{offhand: guid}, :offhand), do: guid
  defp slot_guid(%Player{ranged: guid}, :ranged), do: guid

  defp usable_weapon(character, hand) do
    case CombatWeapon.usable(character, hand) do
      %ItemTemplate{delay: delay} = weapon when is_integer(delay) and delay > 0 -> weapon
      _unavailable -> nil
    end
  end
end
