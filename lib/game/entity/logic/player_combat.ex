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
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @initiated_grace_ms 5_000

  def mark_attacked(%Character{internal: %Internal{} = internal} = character, now) when is_integer(now) do
    %{character | internal: %{internal | in_combat: true, last_hostile_time: now}}
    |> CombatLogic.sync_combat_flag()
  end

  def mark_attacked(character, _now), do: character

  def mark_initiated(%Character{internal: %Internal{} = internal} = character, now) when is_integer(now) do
    internal =
      %{internal | in_combat: true, last_hostile_time: now}
      |> Map.put(:hostile_initiated_at, now)

    %{character | internal: internal}
    |> CombatLogic.sync_combat_flag()
  end

  def mark_initiated(character, _now), do: character

  def sync(character, %Blackboard{} = blackboard) do
    sync(character, blackboard, Time.now())
  end

  def sync(%Character{internal: %Internal{in_combat: true}} = character, %Blackboard{} = blackboard, now)
      when is_integer(now) do
    cond do
      has_attackers?(character) ->
        {character |> clear_initiated() |> CombatLogic.sync_combat_flag(), blackboard}

      auto_attacking_target?(character, blackboard) or recently_initiated?(character, now) ->
        {CombatLogic.sync_combat_flag(character), blackboard}

      true ->
        {clear(character), Blackboard.clear_auto_attack(blackboard)}
    end
  end

  def sync(character, %Blackboard{} = blackboard, _now), do: {character, blackboard}

  defp clear(%Character{internal: %Internal{} = internal} = character) do
    %{character | internal: %{internal | in_combat: false}}
    |> CombatLogic.sync_combat_flag()
  end

  defp clear_initiated(%Character{internal: %Internal{} = internal} = character) do
    case Map.get(internal, :hostile_initiated_at) do
      nil -> character
      _initiated_at -> %{character | internal: Map.put(internal, :hostile_initiated_at, nil)}
    end
  end

  defp recently_initiated?(%Character{internal: %Internal{} = internal}, now) do
    case Map.get(internal, :hostile_initiated_at) do
      initiated_at when is_integer(initiated_at) -> now - initiated_at < @initiated_grace_ms
      _ -> false
    end
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
