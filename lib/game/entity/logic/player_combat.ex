defmodule ThistleTea.Game.Entity.Logic.PlayerCombat do
  @moduledoc """
  Player combat state as a self-healing derived property.

  A player is "in combat" while on at least one mob's threat table (vmangos:
  PvE combat ends only when the hostile-ref list empties), while actively
  auto-attacking a live target, or within a short drop window of the last
  hostile event — the timer covers PvP and hostile actions that created no
  threat entry. Mobs announce table membership with `threat_ref_gained`/
  `threat_ref_lost` casts and the player keeps the referencing mob guids in
  `internal.threat_refs`; because it is a set owned by the player process,
  release messages are idempotent, and the per-tick `sync/3` prunes refs
  whose mob is dead or gone, a missed release can never pin a player in
  combat — the state always converges.
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

  def vanish(%Character{internal: %Internal{} = internal} = character) do
    refs = internal.threat_refs || MapSet.new()
    blackboard = internal.blackboard |> Blackboard.from_any() |> Blackboard.clear_auto_attack()

    character =
      %{
        character
        | internal: %{
            internal
            | threat_refs: MapSet.new(),
              in_combat: false,
              last_hostile_time: nil,
              blackboard: blackboard
          }
      }
      |> CombatLogic.sync_combat_flag()

    {character, MapSet.to_list(refs)}
  end

  def vanish(character), do: {character, []}

  def gain_threat_ref(%Character{internal: %Internal{} = internal} = character, mob_guid)
      when is_integer(mob_guid) and mob_guid > 0 do
    refs = MapSet.put(internal.threat_refs || MapSet.new(), mob_guid)

    %{character | internal: %{internal | threat_refs: refs, in_combat: true}}
    |> CombatLogic.sync_combat_flag()
  end

  def gain_threat_ref(character, _mob_guid), do: character

  def lose_threat_ref(%Character{internal: %Internal{threat_refs: %MapSet{} = refs} = internal} = character, mob_guid) do
    %{character | internal: %{internal | threat_refs: MapSet.delete(refs, mob_guid)}}
  end

  def lose_threat_ref(character, _mob_guid), do: character

  def sync(character, %Blackboard{} = blackboard) do
    sync(character, blackboard, Time.now())
  end

  def sync(%Character{internal: %Internal{in_combat: true}} = character, %Blackboard{} = blackboard, now)
      when is_integer(now) do
    if auto_attacking_target?(character, blackboard) do
      {character |> touch_hostile(now) |> CombatLogic.sync_combat_flag(), blackboard}
    else
      character = prune_threat_refs(character)

      if threat_refs?(character) or within_drop_window?(character, now) do
        {CombatLogic.sync_combat_flag(character), Blackboard.clear_auto_attack(blackboard)}
      else
        {clear(character), Blackboard.clear_auto_attack(blackboard)}
      end
    end
  end

  def sync(character, %Blackboard{} = blackboard, _now), do: {character, blackboard}

  defp prune_threat_refs(%Character{internal: %Internal{threat_refs: %MapSet{} = refs} = internal} = character) do
    %{character | internal: %{internal | threat_refs: MapSet.filter(refs, &referencing_mob_active?/1)}}
  end

  defp prune_threat_refs(character), do: character

  defp threat_refs?(%Character{internal: %Internal{threat_refs: %MapSet{} = refs}}), do: MapSet.size(refs) > 0
  defp threat_refs?(_character), do: false

  defp referencing_mob_active?(mob_guid) do
    case Metadata.query(mob_guid, [:alive?]) do
      %{alive?: true} -> true
      _ -> false
    end
  end

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
