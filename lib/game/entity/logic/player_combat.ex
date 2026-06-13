defmodule ThistleTea.Game.Entity.Logic.PlayerCombat do
  @moduledoc """
  Player combat-state bookkeeping driven by incoming attacks and attacker
  metadata.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def mark_attacked(%Character{internal: %Internal{} = internal} = character, now) when is_integer(now) do
    %{character | internal: %{internal | in_combat: true, last_hostile_time: now}}
  end

  def mark_attacked(character, _now), do: character

  def sync(%Character{internal: %Internal{in_combat: true}} = character, %Blackboard{} = blackboard) do
    if active?(character, blackboard) do
      {character, blackboard}
    else
      {clear(character), Blackboard.clear_attack(blackboard)}
    end
  end

  def sync(character, %Blackboard{} = blackboard), do: {character, blackboard}

  defp clear(%Character{internal: %Internal{} = internal} = character) do
    %{character | internal: %{internal | in_combat: false}}
  end

  defp active?(%Character{} = character, %Blackboard{} = blackboard) do
    has_attackers?(character) or auto_attacking_target?(character, blackboard)
  end

  defp has_attackers?(%Character{object: %Object{guid: guid}}) when is_integer(guid) do
    case Metadata.query(guid, [:attacker_count]) do
      %{attacker_count: count} when is_number(count) and count > 0 -> true
      _ -> false
    end
  end

  defp has_attackers?(_character), do: false

  defp auto_attacking_target?(%Character{} = character, %Blackboard{auto_attacking: true}) do
    active_target?(character)
  end

  defp auto_attacking_target?(_character, _blackboard), do: false

  defp active_target?(%Character{internal: %Internal{map: map}, unit: %Unit{target: target}})
       when is_integer(target) and target > 0 do
    case World.target_position(target) do
      {^map, _x, _y, _z} -> target_alive?(target)
      _ -> false
    end
  end

  defp active_target?(_character), do: false

  defp target_alive?(target) do
    case Metadata.query(target, [:alive?]) do
      %{alive?: false} -> false
      _ -> true
    end
  end
end
