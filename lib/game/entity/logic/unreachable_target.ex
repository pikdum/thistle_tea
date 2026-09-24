defmodule ThistleTea.Game.Entity.Logic.UnreachableTarget do
  @moduledoc "Tracks failed pursuit until contact, a successful route, or the shared evade timeout."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Guid

  @timeout_ms 24_000
  @no_unreachable_evade 0x8
  @controlled_flags 0x00040000 + 0x00400000 + 0x00800000

  def record(%Mob{} = entity, target, reachable?, now) do
    blackboard = Blackboard.ensure(entity.internal.blackboard)
    navigation = blackboard.navigation

    navigation =
      if target == entity.unit.target and is_integer(target) and target > 0 and
           not reachable? and eligible?(entity, blackboard) do
        since = if navigation.unreachable_target == target, do: navigation.unreachable_since || now, else: now
        %{navigation | unreachable_target: target, unreachable_since: since}
      else
        %{navigation | unreachable_target: nil, unreachable_since: nil}
      end

    if navigation == blackboard.navigation,
      do: entity,
      else: %{entity | internal: %{entity.internal | blackboard: %{blackboard | navigation: navigation}}}
  end

  def record(entity, _target, _reachable?, _now), do: entity

  def maintain(%Mob{} = entity, %Context{now: now, perception: perception}) do
    blackboard = Blackboard.ensure(entity.internal.blackboard)
    target = blackboard.navigation.unreachable_target

    if is_integer(target) and
         (target != entity.unit.target or not eligible?(entity, blackboard) or contact?(entity, target, perception)),
       do: record(entity, target, true, now),
       else: entity
  end

  def maintain(entity, _context), do: entity

  def expired?(%Mob{} = entity, %Blackboard{navigation: navigation} = blackboard, now) do
    is_integer(navigation.unreachable_since) and navigation.unreachable_target == entity.unit.target and
      eligible?(entity, blackboard) and now - navigation.unreachable_since > @timeout_ms
  end

  def expired?(_entity, _blackboard, _now), do: false

  defp eligible?(%Mob{internal: internal} = entity, blackboard) do
    extra_flags = if internal.creature, do: internal.creature.extra_flags || 0, else: 0

    internal.in_combat == true and (extra_flags &&& @no_unreachable_evade) == 0 and
      free_movement?(entity) and not player_controlled?(entity) and
      Blackboard.combat_movement?(blackboard, entity)
  end

  defp free_movement?(%Mob{internal: internal, unit: unit} = entity) do
    ((unit.flags || 0) &&& @controlled_flags) == 0 and not Movement.blocked?(entity) and internal.rooted? != true
  end

  defp player_controlled?(%Mob{unit: unit}) do
    Guid.entity_type(unit.summoned_by) == :player or Guid.entity_type(unit.charmed_by) == :player
  end

  defp contact?(entity, target, perception) do
    metadata = Perception.metadata(perception, target) || %{}
    reach = Combat.melee_reach(entity.unit.combat_reach || 1.5, Map.get(metadata, :combat_reach) || 1.5)
    distance = Perception.distance(perception, target)
    is_number(distance) and distance <= reach and Perception.line_of_sight?(perception, target)
  end
end
