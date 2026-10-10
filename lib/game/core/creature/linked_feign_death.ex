defmodule ThistleTea.Game.Core.Creature.LinkedFeignDeath do
  @moduledoc """
  Scripted lethal-damage prevention with a delayed revival check against nearby
  fighting creatures. Fallen creatures retain their threat and tap, but stop
  moving, attacking, receiving damage, and regenerating until they revive or
  die. Script hooks supply the encounter's visuals and text.
  """

  import Bitwise, only: [band: 2, bor: 2, bnot: 1]

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Spell.Casting

  @enforce_keys [:entry, :radius, :delay_ms]
  defstruct [:entry, :radius, :delay_ms, :revive_at, :pacify_spell, fall_steps: [], revive_steps: []]

  @dead_flag 0x20

  def active?(%Mob{internal: %{linked_feign_death: %__MODULE__{revive_at: at}}}), do: is_integer(at)
  def active?(_entity), do: false

  def observation_radius(%Mob{internal: %{linked_feign_death: %__MODULE__{radius: radius}}} = mob),
    do: if(active?(mob), do: radius, else: 0.0)

  def observation_radius(_entity), do: 0.0

  def prevent(%Mob{internal: %{linked_feign_death: %__MODULE__{} = link}} = mob, health, damage, now)
      when health > 0 and damage >= health do
    mob = mob |> Casting.cancel(now) |> Movement.stop(now) |> remove_auras(now)
    blackboard = mob.internal.blackboard |> Blackboard.ensure() |> Blackboard.clear_chase() |> Blackboard.clear_attack()
    unit = %{mob.unit | stand_state: 7, dynamic_flags: bor(mob.unit.dynamic_flags || 0, @dead_flag)}
    internal = %{mob.internal | linked_feign_death: %{link | revive_at: now + link.delay_ms}, blackboard: blackboard}
    mob = Entity.mark_broadcast_update(%{mob | unit: unit, internal: internal})

    effects =
      if is_integer(unit.target) and unit.target > 0,
        do: [Effects.attack_stop(mob.object.guid, unit.target)],
        else: []

    mob = Effects.enqueue(mob, effects ++ [Effects.script_steps(link.fall_steps, mob.object.guid, 0)])
    {mob, max(health - 1, 0)}
  end

  def prevent(entity, _health, damage, _now), do: {entity, damage}

  def reset(entity, now, heal? \\ true)

  def reset(%Mob{internal: %{linked_feign_death: %__MODULE__{revive_at: at} = link}} = mob, now, heal?)
      when is_integer(at) do
    {mob, events} = Aura.remove_spells(mob, List.wrap(link.pacify_spell), now)
    unit = %{mob.unit | stand_state: 0, dynamic_flags: band(mob.unit.dynamic_flags || 0, bnot(@dead_flag))}
    internal = %{mob.internal | linked_feign_death: %{link | revive_at: nil}}
    mob = %{mob | unit: unit, internal: internal} |> Effects.enqueue(events) |> Entity.mark_broadcast_update()
    if heal? and not Entity.dead?(mob), do: Entity.heal(mob, mob.unit.max_health), else: mob
  end

  def reset(entity, _now, _heal?), do: entity

  def tick(%Mob{internal: %{linked_feign_death: %__MODULE__{revive_at: at} = link}} = mob, blackboard, context)
      when is_integer(at) do
    cond do
      not fighting_target?(mob, context.perception) ->
        mob = reset(mob, context.now)
        {:failure, mob, blackboard}

      context.now < at ->
        {BT.running(min(at - context.now, 1_000), :feigned_death), mob, blackboard}

      living_peer?(mob, link, context.perception) ->
        mob = reset(mob, context.now)
        {mob, blackboard} = Script.run(mob, blackboard, link.revive_steps, mob.object.guid, context)
        {:failure, mob, blackboard}

      true ->
        mob = mob |> Entity.kill(context.now) |> Effects.enqueue(Effects.despawn_self(0, 0))
        {BT.running(1_000, :dead), mob, mob.internal.blackboard}
    end
  end

  def tick(mob, blackboard, %Context{}), do: {:failure, mob, blackboard}

  defp fighting_target?(%Mob{internal: %{in_combat: true, threat: threat, world: world}}, perception) do
    Enum.any?(threat || %{}, fn {guid, _threat} ->
      match?(%{alive?: true}, Perception.metadata(perception, guid)) and
        match?({^world, _, _, _}, Perception.position(perception, guid))
    end)
  end

  defp fighting_target?(_mob, _perception), do: false

  defp living_peer?(mob, link, perception) do
    world = mob.internal.world

    perception
    |> Perception.nearby(:mobs, link.radius)
    |> Enum.any?(fn {guid, _distance} ->
      guid != mob.object.guid and Perception.entry(perception, guid) == link.entry and
        match?({^world, _, _, _}, Perception.position(perception, guid)) and
        case Perception.metadata(perception, guid) do
          %{in_combat: true, health: health} when health > 1 -> true
          _ -> false
        end
    end)
  end

  defp remove_auras(mob, now) do
    {mob, events} = Aura.transition(mob, %Aura.Change{holders: [], cause: :removed, now: now})
    Effects.enqueue(mob, events)
  end
end
