defmodule ThistleTea.Game.Entity.Logic.AI.BT.Distancing do
  @moduledoc "Moves to a target-relative distance without changing combat ownership or threat."

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Distancing, as: Memory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Spell.Cast

  def start(%Mob{} = mob, blackboard, target_guid, distance, %Context{perception: perception} = context)
      when is_number(distance) and distance > 0 do
    if allowed?(mob) and target_guid != mob.object.guid and Navigation.target_alive_same_map?(mob, target_guid, context) do
      {_, tx, ty, tz} = Perception.position(perception, target_guid)
      {x, y, _, _} = mob.movement_block.position
      angle = :math.atan2(y - ty, x - tx)
      radius = distance + bounding_radius(Perception.metadata(perception, target_guid))
      destination = {tx + radius * :math.cos(angle), ty + radius * :math.sin(angle), tz}

      memory = %Memory{
        target_guid: target_guid,
        target_position: {tx, ty, tz},
        destination: destination,
        combat?: mob.internal.in_combat == true,
        victim_guid: mob.unit.target
      }

      blackboard = %{blackboard | distancing: memory}
      mob = %{mob | internal: %{mob.internal | blackboard: blackboard}}
      {NavigationIntent.enqueue(mob, destination, distancing?: true), blackboard}
    else
      {mob, blackboard}
    end
  end

  def start(mob, blackboard, _target, _distance, _context), do: {mob, blackboard}

  def allowed?(%Mob{} = mob) do
    not Fear.blocked?(mob) and not Movement.blocked?(mob) and not ControlMovement.active?(mob) and
      not Aura.has_aura?(mob, :feign_death) and not match?(%{possessed?: true}, mob.internal.pet) and
      mob.movement_block.transport_guid in [nil, 0] and
      not Blackboard.fleeing?(Blackboard.ensure(mob.internal.blackboard))
  end

  def allowed?(_entity), do: false

  def accept(%Mob{} = mob, [_ | _] = path, now) do
    {mob, events} = Movement.stop_with_effects(mob, now)

    mob =
      mob
      |> Effects.enqueue(events)
      |> interrupt_cast(now)
      |> Movement.move_along_path(path, [run?: true, distancing?: true], now)

    blackboard = mob.internal.blackboard |> Blackboard.clear_chase() |> Blackboard.clear_move_target()
    memory = %{blackboard.distancing | started?: true}
    %{mob | internal: %{mob.internal | blackboard: %{blackboard | distancing: memory}}}
  end

  def reject(%Mob{internal: %{blackboard: %Blackboard{} = blackboard}} = mob),
    do: %{mob | internal: %{mob.internal | blackboard: %{blackboard | distancing: nil}}}

  def maintain(%Mob{internal: %{blackboard: %Blackboard{distancing: %Memory{} = memory}}} = mob, context) do
    if interrupted?(mob, memory, context), do: cancel(mob, context.now), else: mob
  end

  def maintain(entity, _context), do: entity

  def tick(%Mob{} = mob, %Blackboard{distancing: %Memory{started?: false}} = blackboard, _context),
    do: {BT.running(0, :navigation), mob, blackboard}

  def tick(%Mob{} = mob, %Blackboard{distancing: %Memory{}} = blackboard, %Context{now: now}) do
    if Movement.moving?(mob, now) do
      {BT.running(min(Movement.next_spatial_update_delay(mob, now), 500), :distancing), mob, blackboard}
    else
      blackboard = %{blackboard | distancing: nil} |> Blackboard.reset_deadline(:next_spell_list_at)
      {:failure, %{mob | internal: %{mob.internal | blackboard: blackboard}}, blackboard}
    end
  end

  def tick(entity, blackboard, _context), do: {:failure, entity, blackboard}

  def target_guid(%{internal: %{blackboard: %Blackboard{distancing: %Memory{target_guid: guid}}}}), do: guid
  def target_guid(_entity), do: nil

  def active?(entity), do: not is_nil(target_guid(entity))

  defp interrupted?(mob, memory, context) do
    not allowed?(mob) or mob.internal.in_combat == true != memory.combat? or mob.unit.target != memory.victim_guid or
      not Navigation.target_alive_same_map?(mob, memory.target_guid, context) or
      (memory.started? and Movement.moving?(mob, context.now) and not own_movement?(mob))
  end

  defp cancel(mob, now) do
    mob =
      if own_movement?(mob) do
        {mob, events} = Movement.stop_with_effects(mob, now)
        Effects.enqueue(mob, events)
      else
        mob
      end

    reject(mob)
  end

  defp own_movement?(mob), do: Keyword.get(mob.internal.movement_options || [], :distancing?, false)

  defp interrupt_cast(%{internal: %{casting: %Cast{spell: spell}}} = mob, now) do
    if Bitwise.band(spell.interrupt_flags || 0, 1) == 0, do: mob, else: Casting.interrupt(mob, now)
  end

  defp interrupt_cast(mob, _now), do: mob

  defp bounding_radius(%{bounding_radius: radius}) when is_number(radius), do: max(radius, 0)
  defp bounding_radius(_metadata), do: 0.0
end
