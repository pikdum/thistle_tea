defmodule ThistleTea.Game.Entity.Logic.PlayerCombat do
  @moduledoc """
  Player combat state as a self-healing derived property.

  A player is "in combat" while actively auto-attacking a live target or within
  a short drop window of the last hostile event to or from them.
  `internal.last_hostile_time` is the single source of truth: it is refreshed
  when the player is attacked, initiates a hostile action, or is actively
  swinging a live target, and the per-tick `sync/3` clears combat once the
  window lapses. Nothing here reads a cross-process attacker counter, so a
  stale count can never pin a player in combat — the timer always expires.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @combat_drop_ms 5_000

  def mark_attacked(%Character{internal: %Internal{} = internal} = character, now) when is_integer(now) do
    %{character | internal: %{internal | in_combat: true, last_hostile_time: now}}
    |> CombatLogic.sync_combat_flag()
  end

  def mark_attacked(character, _now), do: character

  def mark_initiated(character, now), do: mark_attacked(character, now)

  def sync(character, %Blackboard{} = blackboard) do
    sync(character, blackboard, Time.now())
  end

  def sync(%Character{internal: %Internal{in_combat: true}} = character, %Blackboard{} = blackboard, now)
      when is_integer(now) do
    cond do
      auto_attacking_target?(character, blackboard) ->
        {character |> touch_hostile(now) |> CombatLogic.sync_combat_flag(), blackboard}

      within_drop_window?(character, now) ->
        {CombatLogic.sync_combat_flag(character), Blackboard.clear_auto_attack(blackboard)}

      true ->
        {clear(character), Blackboard.clear_auto_attack(blackboard)}
    end
  end

  def sync(character, %Blackboard{} = blackboard, _now), do: {character, blackboard}

  defp touch_hostile(%Character{internal: %Internal{} = internal} = character, now) do
    %{character | internal: %{internal | last_hostile_time: now}}
  end

  defp within_drop_window?(%Character{internal: %Internal{last_hostile_time: last}}, now)
       when is_integer(last) and is_integer(now) do
    now - last < @combat_drop_ms
  end

  defp within_drop_window?(_character, _now), do: false

  defp clear(%Character{internal: %Internal{} = internal} = character) do
    %{character | internal: %{internal | in_combat: false}}
    |> CombatLogic.sync_combat_flag()
  end

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
      %{alive?: true} -> true
      _ -> false
    end
  end
end
