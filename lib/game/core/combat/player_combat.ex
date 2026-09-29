defmodule ThistleTea.Game.Core.Combat.PlayerCombat do
  @moduledoc """
  Player combat state as a self-healing derived property.

  A player is "in combat" while on at least one mob's threat table (vmangos:
  PvE combat ends only when the hostile-ref list empties), or within a window of the last
  hostile event — the timer covers PvP and hostile actions that created no
  threat entry. Mobs announce table membership with `threat_ref_gained`/
  `threat_ref_lost` casts and the player keeps the referencing mob incarnations in
  `internal.threat_refs`; because it is a set owned by the player process,
  release messages are idempotent, and the per-tick `sync/3` prunes refs
  whose mob is dead, gone, or has respawned, so a missed release can never
  pin a player in combat — the state always converges.

  Combat synchronization consumes an immutable context captured by the owner;
  the core never queries world state while making the transition.
  """
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Blackboard.Combat
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat, as: CombatLogic
  alias ThistleTea.Game.Core.Combat.CombatReferences
  alias ThistleTea.Game.Core.Combat.CombatState
  alias ThistleTea.Game.Core.Combat.CombatTimer
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.ControlledCombat
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.Spell.AutoRepeat
  alias ThistleTea.Game.Core.Spell.MeleeSpell

  def projection(%Character{} = character) do
    %{
      combat_victim_guid: attack_target(character),
      combat_targets: character.internal.threat_refs |> Kernel.||(MapSet.new()) |> threat_ref_guids() |> Enum.sort()
    }
  end

  defp attack_target(%Character{
         internal: %Internal{
           in_combat: true,
           blackboard: %Blackboard{combat: %Combat{auto_attacking: true, auto_attack_target: %TargetRef{guid: guid}}}
         }
       }), do: guid

  defp attack_target(%Character{internal: %Internal{in_combat: true}} = character), do: ranged_target(character)
  defp attack_target(_character), do: nil

  defp ranged_target(%Character{internal: %Internal{auto_shot: %{target_guid: guid}}}), do: guid
  defp ranged_target(_character), do: nil

  def mark_attacked(character, now, faction_id \\ nil, opponent \\ nil)

  def mark_attacked(%Character{} = character, now, faction_id, opponent) when is_integer(now) do
    character
    |> CombatTimer.attacked(opponent, now)
    |> CombatLogic.sync_combat_flag()
    |> mark_temporary_at_war(faction_id)
  end

  def mark_attacked(character, _now, _faction_id, _opponent), do: character

  def hold_combat(%Character{} = character, now, duration, opponent \\ nil)
      when is_integer(now) and is_integer(duration) and duration >= 0 do
    character |> CombatTimer.hold(now, duration, opponent) |> CombatLogic.sync_combat_flag()
  end

  def mark_initiated(character, now, opponent, timed? \\ nil)

  def mark_initiated(%Character{} = character, now, opponent, timed?) do
    character |> CombatTimer.attack(opponent, now, timed?) |> CombatLogic.sync_combat_flag()
  end

  def mark_initiated(entity, _now, _opponent, _timed?), do: entity

  def mark_hostile_contact(%Character{object: %{guid: guid}, unit: %Unit{health: health}} = character, other_guid, now)
      when is_integer(other_guid) and other_guid > 0 and other_guid != guid and is_number(health) and health > 0 do
    if Guid.entity_type(other_guid) in [:player, :mob, :pet],
      do: mark_attacked(character, now, nil, other_guid),
      else: character
  end

  def mark_hostile_contact(character, _other_guid, _now), do: character

  def mark_temporary_at_war(
        %Character{player: %Player{reputation: %Reputation{} = reputation} = player} = character,
        faction_id
      ) do
    case Reputation.set_temporary_at_war(reputation, faction_id) do
      {:ok, reputation, change} ->
        character = %{character | player: %{player | reputation: reputation}}
        Effects.enqueue(character, Effects.faction_at_war_changed(change.index, true))

      {:error, :not_allowed} ->
        character
    end
  end

  def mark_temporary_at_war(character, _faction_id), do: character

  def start_melee_attack(%Character{} = character, %TargetRef{} = target) do
    previous = Blackboard.auto_attack_target(character.internal.blackboard)

    if previous == target do
      {character, []}
    else
      {character, effects} = if previous, do: stop_melee_attack(character), else: {character, []}

      blackboard =
        character.internal.blackboard
        |> Blackboard.ensure()
        |> Blackboard.clear_attack_started()
        |> Blackboard.enable_auto_attack(target)

      {%{
         character
         | unit: %{character.unit | target: target.guid},
           internal: %{character.internal | blackboard: blackboard}
       }, effects}
    end
  end

  def stop_attack(%Character{} = character) do
    {character, ranged_effects} = AutoRepeat.cancel(character)
    {character, melee_effects} = stop_melee_attack(character)
    {character, ranged_effects ++ melee_effects}
  end

  def stop_attack(character), do: {character, []}

  def stop_melee_attack(
        %Character{object: %{guid: guid}, unit: %Unit{} = unit, internal: %Internal{} = internal} = character
      ) do
    target = Blackboard.auto_attack_target(internal.blackboard)
    blackboard = internal.blackboard |> Blackboard.ensure() |> Blackboard.clear_auto_attack()
    unit = if target, do: %{unit | target: 0}, else: unit

    character =
      %{character | unit: unit, internal: %{internal | blackboard: blackboard}}
      |> MeleeSpell.interrupt()

    character = if target, do: Entity.mark_broadcast_update(character), else: character
    {character, attack_stop_effects(guid, target)}
  end

  def stop_melee_attack(character), do: {character, []}

  def disengage(%Character{} = character) do
    {character, attack_effects} = stop_attack(character)
    %Character{internal: %Internal{} = internal} = character
    refs = internal.threat_refs || MapSet.new()

    character =
      %{
        character
        | unit: %{character.unit | target: 0},
          internal: %{
            internal
            | threat_refs: MapSet.new(),
              in_combat: false
          }
      }
      |> CombatTimer.clear()
      |> CombatLogic.sync_combat_flag()

    effects =
      attack_effects ++
        [Effects.drop_nearby_threat()] ++
        Enum.map(threat_ref_guids(refs), &Effects.drop_threat/1)

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
              undetectable_until: now + 1_000,
              blackboard: blackboard
          }
      }
      |> CombatTimer.clear()
      |> CombatLogic.sync_combat_flag()

    {character, temporary_war_effects} = clear_temporary_at_war(character)
    character = Effects.enqueue(character, temporary_war_effects)
    {character, threat_ref_guids(refs)}
  end

  def vanish(character, _now), do: {character, []}

  def undetectable?(%Character{internal: %Internal{undetectable_until: expires_at}}, now)
      when is_integer(expires_at) and is_integer(now), do: expires_at > now

  def undetectable?(_character, _now), do: false

  def gain_threat_ref(
        %Character{internal: %Internal{} = internal, unit: %Unit{health: health}} = character,
        mob_guid,
        incarnation_id,
        now
      )
      when is_number(health) and health > 0 and is_integer(mob_guid) and mob_guid > 0 and is_integer(incarnation_id) and
             incarnation_id > 0 and is_integer(now) do
    refs = MapSet.put(internal.threat_refs || MapSet.new(), {mob_guid, incarnation_id})

    %{character | internal: %{internal | threat_refs: refs}} |> CombatState.enter(now)
  end

  def gain_threat_ref(character, _mob_guid, _incarnation_id, _now), do: character

  def lose_threat_ref(
        %Character{internal: %Internal{threat_refs: %MapSet{} = refs} = internal} = character,
        mob_guid,
        incarnation_id
      ) do
    %{character | internal: %{internal | threat_refs: MapSet.delete(refs, {mob_guid, incarnation_id})}}
  end

  def lose_threat_ref(character, _mob_guid, _incarnation_id), do: character

  def sync(%Character{} = character, %Blackboard{} = blackboard, %Context{} = context) do
    {character, blackboard} =
      if Blackboard.auto_attack_target(blackboard) &&
           not auto_attacking_target?(character, blackboard, context.perception) do
        character = %{character | internal: %{character.internal | blackboard: blackboard}}
        {character, effects} = stop_melee_attack(character)
        {Effects.enqueue(character, effects), character.internal.blackboard}
      else
        {character, blackboard}
      end

    sync_combat(character, blackboard, context)
  end

  def sync(character, %Blackboard{} = blackboard, %Context{}), do: {character, blackboard}

  defp sync_combat(
         %Character{internal: %Internal{in_combat: true}} = character,
         %Blackboard{} = blackboard,
         %Context{now: now} = context
       ) do
    character = prune_threat_refs(character, context.perception)

    if threat_refs?(character) or ControlledCombat.holds_combat?(character, context) or
         CombatTimer.remaining(character, now) > 0 or Aura.has_aura?(character, :interrupt_regen) do
      {CombatLogic.sync_combat_flag(character), blackboard}
    else
      {clear(character), blackboard}
    end
  end

  defp sync_combat(character, blackboard, _context), do: {character, blackboard}

  defp prune_threat_refs(%Character{internal: %Internal{} = internal} = character, perception) do
    refs = CombatReferences.prune(internal.threat_refs, internal.world, perception)
    %{character | internal: %{internal | threat_refs: refs}}
  end

  defp threat_refs?(%Character{internal: %Internal{threat_refs: %MapSet{} = refs}}), do: MapSet.size(refs) > 0

  defp threat_ref_guids(refs) do
    refs
    |> Enum.map(fn {mob_guid, _incarnation_id} -> mob_guid end)
    |> Enum.uniq()
  end

  defp attack_stop_effects(source_guid, %TargetRef{guid: target_guid})
       when is_integer(source_guid) and is_integer(target_guid) and target_guid > 0 do
    [Effects.attack_stop(source_guid, target_guid)]
  end

  defp attack_stop_effects(_source_guid, _target_guid), do: []

  defp clear(%Character{internal: %Internal{} = internal} = character) do
    character =
      %{character | internal: %{internal | in_combat: false}}
      |> CombatTimer.clear()
      |> CombatLogic.sync_combat_flag()

    {character, effects} = clear_temporary_at_war(character)
    Effects.enqueue(character, effects)
  end

  defp clear_temporary_at_war(%Character{player: %Player{reputation: %Reputation{} = reputation} = player} = character) do
    {reputation, changes} = Reputation.clear_temporary_at_war(reputation)
    character = %{character | player: %{player | reputation: reputation}}
    effects = Enum.map(changes, &Effects.faction_at_war_changed(&1.index, false))
    {character, effects}
  end

  defp clear_temporary_at_war(character), do: {character, []}

  defp auto_attacking_target?(
         %Character{} = character,
         %Blackboard{combat: %Combat{auto_attacking: true, auto_attack_target: %TargetRef{} = target}},
         perception
       ) do
    active_target?(character, target, perception)
  end

  defp auto_attacking_target?(_character, _blackboard, _perception), do: false

  defp active_target?(%Character{internal: %Internal{world: world}}, %TargetRef{guid: target} = target_ref, perception)
       when is_integer(target) and target > 0 do
    case Perception.position(perception, target) do
      {^world, _x, _y, _z} -> TargetRef.active?(target_ref, Perception.metadata(perception, target) || %{})
      _ -> false
    end
  end

  defp active_target?(_character, _target_ref, _perception), do: false
end
