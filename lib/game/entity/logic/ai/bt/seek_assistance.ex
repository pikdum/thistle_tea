defmodule ThistleTea.Game.Entity.Logic.AI.BT.SeekAssistance do
  @moduledoc "Retreats to an observed ally, calls for assistance on arrival, and waits for its reaction."

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Assistance, as: Memory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement

  def maintain(%Mob{internal: %{blackboard: %Blackboard{assistance: %Memory{} = memory} = blackboard}} = mob, context) do
    cond do
      mob.internal.in_combat != true or mob.unit.target != memory.enemy_guid or
        not Navigation.target_alive_same_map?(mob, memory.enemy_guid, context) or ControlMovement.active?(mob) ->
        {_, mob, blackboard} = finish(mob, blackboard, context.now)
        %{mob | internal: %{mob.internal | blackboard: blackboard}}

      Fear.blocked?(mob) and is_nil(memory.wait_until) ->
        {mob, events} = Movement.stop_with_effects(mob, context.now)
        blackboard = %{blackboard | assistance: %{memory | requested?: false}}
        mob = Effects.enqueue(mob, events)
        %{mob | internal: %{mob.internal | blackboard: blackboard}}

      true ->
        mob
    end
  end

  def maintain(entity, _context), do: entity

  def tick(%Mob{} = mob, %Blackboard{assistance: %Memory{} = memory} = blackboard, %Context{now: now} = context) do
    cond do
      Fear.blocked?(mob) ->
        {BT.running(500, :assistance), mob, blackboard}

      is_integer(memory.wait_until) ->
        if now >= memory.wait_until,
          do: finish(mob, blackboard, now),
          else: {BT.running(memory.wait_until - now, :assistance), mob, blackboard}

      not memory.requested? ->
        opts = [run?: false, speed_type: :run_speed]
        mob = Navigation.move_to(mob, memory.destination, opts, context)
        {BT.running(0, :navigation), mob, %{blackboard | assistance: %{memory | requested?: true}}}

      Movement.moving?(mob, now) ->
        {BT.running(Movement.next_spatial_update_delay(mob, now), :movement), mob, blackboard}

      true ->
        mob = Effects.enqueue(mob, Effects.call_assistance(memory.enemy_guid))
        memory = %{memory | wait_until: now + Assistance.delay_ms()}
        {BT.running(Assistance.delay_ms(), :assistance), mob, %{blackboard | assistance: memory}}
    end
  end

  def tick(mob, blackboard, _context), do: {:failure, mob, blackboard}

  defp finish(mob, blackboard, now) do
    {mob, events} = Movement.stop_with_effects(mob, now)
    blackboard = %{Blackboard.clear_chase(blackboard) | assistance: nil}
    mob = Effects.enqueue(mob, events)
    internal = %{mob.internal | broadcast_update?: true, blackboard: blackboard}
    {:failure, %{mob | internal: internal}, blackboard}
  end
end
