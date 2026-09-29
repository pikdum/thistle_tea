defmodule ThistleTea.Game.Core.Combat.ZoneCombat do
  @moduledoc "Dungeon-wide combat admission and recurring pulses, bounded by the creature's engagement lifecycle."

  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.CombatZone
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.Combat.CombatLeash
  alias ThistleTea.Game.Core.Combat.CombatZone, as: State
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid

  @pulse_ms 3_000
  @initial_target_radius 533.33333

  def on_enter(%Mob{internal: %{combat_zone: nil}} = entity, source) do
    if CreatureFlags.force_raid_combat?(entity),
      do: %{entity | internal: %{entity.internal | combat_zone: %State{source_guid: source}}},
      else: entity
  end

  def on_enter(entity, _source), do: entity

  def clear(%Mob{} = entity), do: %{entity | internal: %{entity.internal | combat_zone: nil}}

  def next_at(%Mob{internal: %{in_combat: true, combat_zone: %State{source_guid: source, next_at: at}}}, now),
    do: if(is_integer(source), do: now, else: at)

  def next_at(_entity, _now), do: nil

  def observe?(entity, now) do
    case next_at(entity, now) do
      at when is_integer(at) -> at <= now
      _ -> false
    end
  end

  def maintain(%Mob{internal: %{in_combat: true, combat_zone: %State{source_guid: source}}} = entity, context)
      when is_integer(source) do
    entity = clear(entity)
    if player_controlled?(source, context), do: pulse(entity, true, context), else: entity
  end

  def maintain(
        %Mob{internal: %{in_combat: true, combat_zone: %State{next_at: at}}} = entity,
        %Context{now: now} = context
      )
      when is_integer(at) and at <= now do
    entity = %{entity | internal: %{entity.internal | combat_zone: %State{next_at: now + @pulse_ms}}}
    if CombatLeash.should_evade?(entity, now), do: entity, else: pulse(entity, false, context)
  end

  def maintain(entity, _context), do: entity

  def pulse(
        %Mob{internal: %{world: world}} = entity,
        initial?,
        %Context{combat_zone: %CombatZone{world: world, players: [_ | _]}} = context
      ) do
    if eligible?(entity) do
      first? = not match?(%State{next_at: at} when is_integer(at), entity.internal.combat_zone)
      previous = entity.internal.in_combat == true
      entity = %{entity | internal: %{entity.internal | combat_zone: %State{next_at: context.now + @pulse_ms}}}
      nearest = if first? and initial? and entity.unit.target in [nil, 0], do: nearest_hostile(entity, context)
      targets = Enum.uniq(List.wrap(nearest) ++ participants(entity, initial?, context))
      entity = Enum.reduce(targets, entity, &engage(&2, &1, context.now))
      entered(entity, previous, context)
    else
      entity
    end
  end

  def pulse(entity, _initial?, _context), do: entity

  def eligible?(%Mob{internal: %{totem: nil, pet: pet}} = entity) do
    not Entity.dead?(entity) and not CreatureFlags.no_threat_list?(entity) and not player_owned?(pet) and
      not player_guid?(entity.unit.charmed_by)
  end

  def eligible?(_entity), do: false

  defp player_owned?(%Pet{owner_guid: owner}), do: player_guid?(owner)
  defp player_owned?(_pet), do: false

  defp player_guid?(guid), do: is_integer(guid) and guid > 0 and Guid.entity_type(guid) == :player

  defp player_controlled?(guid, %Context{perception: perception}) do
    actor = Perception.actor(perception, guid)
    Enum.any?([guid, actor[:owner_guid], actor[:charmed_by]], &player_guid?/1)
  end

  defp nearest_hostile(entity, %Context{combat_zone: zone, perception: perception} = context) do
    source = Perception.actor(perception, entity.object.guid)

    zone.players
    |> Enum.filter(fn guid ->
      distance = Perception.distance(perception, guid)

      is_number(distance) and distance <= @initial_target_radius and valid_target?(entity, guid, context) and
        Hostility.hostile?(source, Perception.actor(perception, guid))
    end)
    |> Enum.min_by(&{Perception.distance(perception, &1), &1}, fn -> nil end)
  end

  defp participants(entity, initial?, %Context{combat_zone: zone, perception: perception} = context) do
    Enum.flat_map(zone.players, fn player ->
      metadata = Perception.metadata(perception, player) || %{}

      if (initial? or Map.get(metadata, :in_combat) != true) and valid_target?(entity, player, context) do
        with_pet(entity, player, context)
      else
        []
      end
    end)
  end

  defp with_pet(entity, player, %Context{combat_zone: zone} = context) do
    pet = Map.get(zone.pets, player)
    if is_integer(pet) and valid_target?(entity, pet, context), do: [player, pet], else: [player]
  end

  defp valid_target?(%Mob{internal: %{world: world}} = entity, guid, %Context{perception: perception}) do
    match?({^world, _, _, _}, Perception.position(perception, guid)) and
      match?(%{alive?: true}, Perception.metadata(perception, guid)) and
      Hostility.valid_attack_target?(
        Perception.actor(perception, entity.object.guid),
        Perception.actor(perception, guid)
      )
  end

  defp engage(entity, guid, now) do
    opts = if entity.unit.target in [nil, 0], do: [selection: :target], else: [selection: :preserve, contact?: true]
    Engagement.enter(entity, guid, now, opts).entity
  end

  defp entered(%Mob{internal: %{in_combat: true}, unit: %{target: target}} = entity, false, context) do
    entity
    |> MobBT.maybe_enqueue_call_assistance(target)
    |> EventAI.with_blackboard(&EventAI.enter_combat(&1, &2, target, context.now, context))
  end

  defp entered(entity, _previous, _context), do: entity
end
