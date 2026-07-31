defmodule ThistleTea.Game.Entity.Logic.PlayerCombat do
  @moduledoc """
  Player combat state as a self-healing derived property.

  A player is "in combat" while on at least one mob's threat table (vmangos:
  PvE combat ends only when the hostile-ref list empties), while actively
  auto-attacking a live target, or within a short drop window of the last
  hostile event — the timer covers PvP and hostile actions that created no
  threat entry. Mobs announce table membership with `threat_ref_gained`/
  `threat_ref_lost` casts and the player keeps the referencing mob incarnations in
  `internal.threat_refs`; because it is a set owned by the player process,
  release messages are idempotent, and the per-tick `sync/3` prunes refs
  whose mob is dead, gone, or has respawned, so a missed release can never
  pin a player in combat — the state always converges.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Combat
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @combat_drop_ms 5_000

  def mark_attacked(character, now, faction_id \\ nil)

  def mark_attacked(%Character{internal: %Internal{} = internal} = character, now, faction_id) when is_integer(now) do
    %{character | internal: %{internal | in_combat: true, last_hostile_time: now}}
    |> CombatLogic.sync_combat_flag()
    |> mark_temporary_at_war(faction_id)
  end

  def mark_attacked(character, _now, _faction_id), do: character

  def mark_initiated(character, now), do: mark_attacked(character, now)

  def mark_temporary_at_war(
        %Character{player: %Player{reputation: %Reputation{} = reputation} = player} = character,
        faction_id
      ) do
    case ReputationLogic.set_temporary_at_war(reputation, faction_id) do
      {:ok, reputation, change} ->
        character = %{character | player: %{player | reputation: reputation}}
        Effects.enqueue(character, Effects.faction_at_war_changed(change.index, true))

      {:error, :not_allowed} ->
        character
    end
  end

  def mark_temporary_at_war(character, _faction_id), do: character

  def stop_attack(%Character{object: %{guid: guid}, unit: %Unit{} = unit, internal: %Internal{} = internal} = character) do
    {character, auto_repeat_effects} = AutoRepeat.cancel(character)
    blackboard = internal.blackboard |> Blackboard.ensure() |> Blackboard.clear_auto_attack()

    character = %{
      character
      | unit: %{unit | target: 0},
        internal: %{character.internal | blackboard: blackboard}
    }

    {character, auto_repeat_effects ++ attack_stop_effects(guid, unit.target)}
  end

  def stop_attack(character), do: {character, []}

  def disengage(%Character{object: %{guid: guid}} = character) do
    {character, auto_repeat_effects} = AutoRepeat.cancel(character)
    %Character{unit: %Unit{} = unit, internal: %Internal{} = internal} = character
    refs = internal.threat_refs || MapSet.new()
    blackboard = internal.blackboard |> Blackboard.ensure() |> Blackboard.clear_auto_attack()

    character =
      %{
        character
        | unit: %{unit | target: 0},
          internal: %{
            internal
            | threat_refs: MapSet.new(),
              in_combat: false,
              last_hostile_time: nil,
              blackboard: blackboard
          }
      }
      |> CombatLogic.sync_combat_flag()

    effects =
      auto_repeat_effects ++
        [Effects.drop_nearby_threat()] ++
        Enum.map(threat_ref_guids(refs), &Effects.drop_threat/1) ++
        attack_stop_effects(guid, unit.target)

    {character, temporary_war_effects} = clear_temporary_at_war(character)
    {character, effects ++ temporary_war_effects}
  end

  def disengage(character), do: {character, []}

  def vanish(%Character{internal: %Internal{} = internal} = character, now) when is_integer(now) do
    refs = internal.threat_refs || MapSet.new()
    blackboard = internal.blackboard |> Blackboard.ensure() |> Blackboard.clear_auto_attack()

    character =
      %{
        character
        | internal: %{
            internal
            | threat_refs: MapSet.new(),
              in_combat: false,
              last_hostile_time: nil,
              undetectable_until: now + 1_000,
              blackboard: blackboard
          }
      }
      |> CombatLogic.sync_combat_flag()

    {character, temporary_war_effects} = clear_temporary_at_war(character)
    character = Effects.enqueue(character, temporary_war_effects)
    {character, threat_ref_guids(refs)}
  end

  def vanish(character, _now), do: {character, []}

  def undetectable?(%Character{internal: %Internal{undetectable_until: expires_at}}, now)
      when is_integer(expires_at) and is_integer(now), do: expires_at > now

  def undetectable?(_character, _now), do: false

  def gain_threat_ref(%Character{internal: %Internal{} = internal} = character, mob_guid, incarnation_id)
      when is_integer(mob_guid) and mob_guid > 0 and is_integer(incarnation_id) and incarnation_id > 0 do
    refs = MapSet.put(internal.threat_refs || MapSet.new(), {mob_guid, incarnation_id})

    %{character | internal: %{internal | threat_refs: refs, in_combat: true}}
    |> CombatLogic.sync_combat_flag()
  end

  def gain_threat_ref(character, _mob_guid, _incarnation_id), do: character

  def lose_threat_ref(
        %Character{internal: %Internal{threat_refs: %MapSet{} = refs} = internal} = character,
        mob_guid,
        incarnation_id
      ) do
    %{character | internal: %{internal | threat_refs: MapSet.delete(refs, {mob_guid, incarnation_id})}}
  end

  def lose_threat_ref(character, _mob_guid, _incarnation_id), do: character

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

  defp referencing_mob_active?({mob_guid, incarnation_id}) do
    case Metadata.query(mob_guid, [:alive?, :incarnation_id]) do
      %{alive?: true, incarnation_id: ^incarnation_id} -> true
      _ -> false
    end
  end

  defp referencing_mob_active?(_ref), do: false

  defp threat_ref_guids(refs) do
    refs
    |> Enum.map(fn {mob_guid, _incarnation_id} -> mob_guid end)
    |> Enum.uniq()
  end

  defp attack_stop_effects(source_guid, target_guid)
       when is_integer(source_guid) and is_integer(target_guid) and target_guid > 0 do
    [Effects.attack_stop(source_guid, target_guid)]
  end

  defp attack_stop_effects(_source_guid, _target_guid), do: []

  defp touch_hostile(%Character{internal: %Internal{} = internal} = character, now) do
    %{character | internal: %{internal | last_hostile_time: now}}
  end

  defp within_drop_window?(%Character{internal: %Internal{last_hostile_time: last}}, now)
       when is_integer(last) and is_integer(now) do
    now - last < @combat_drop_ms
  end

  defp within_drop_window?(_character, _now), do: false

  defp clear(%Character{internal: %Internal{} = internal} = character) do
    character =
      %{character | internal: %{internal | in_combat: false}}
      |> CombatLogic.sync_combat_flag()

    {character, effects} = clear_temporary_at_war(character)
    Effects.enqueue(character, effects)
  end

  defp clear_temporary_at_war(%Character{player: %Player{reputation: %Reputation{} = reputation} = player} = character) do
    {reputation, changes} = ReputationLogic.clear_temporary_at_war(reputation)
    character = %{character | player: %{player | reputation: reputation}}
    effects = Enum.map(changes, &Effects.faction_at_war_changed(&1.index, false))
    {character, effects}
  end

  defp clear_temporary_at_war(character), do: {character, []}

  defp auto_attacking_target?(%Character{} = character, %Blackboard{
         combat: %Combat{auto_attacking: true, auto_attack_target: %TargetRef{} = target}
       }) do
    active_target?(character, target)
  end

  defp auto_attacking_target?(_character, _blackboard), do: false

  defp active_target?(
         %Character{internal: %Internal{world: world}, unit: %Unit{target: target}},
         %TargetRef{guid: target} = target_ref
       )
       when is_integer(target) and target > 0 do
    case World.target_position(target) do
      {^world, _x, _y, _z} -> target_ref_active?(target_ref)
      _ -> false
    end
  end

  defp active_target?(_character, _target_ref), do: false

  defp target_ref_active?(%TargetRef{guid: target} = target_ref) do
    TargetRef.active?(target_ref, Metadata.query(target, [:alive?, :incarnation_id]) || %{})
  end
end
