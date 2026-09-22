defmodule ThistleTea.Game.Entity.Logic.AI.BT.Flee do
  @moduledoc """
  Timed fleeing shared by scripted creatures and critters, using observed
  source positions and bounded navigation requests.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement

  def tick(%Mob{} = mob, %Blackboard{combat: %{flee_until: until}} = blackboard, %Context{now: now} = context)
      when is_integer(until) do
    cond do
      now >= until or mob.unit.health <= 0 ->
        clear(mob, blackboard)

      Fear.blocked?(mob) or Aura.has_aura?(mob, :prevent_fleeing) ->
        {mob, events} = Movement.stop_with_effects(mob, now)
        {BT.running(min(500, until - now), :flee), Effects.enqueue(mob, events), blackboard}

      Movement.moving?(mob, now) ->
        Navigation.wait_for_arrival(mob, blackboard, context, flee: until - now)

      true ->
        move(mob, blackboard, context)
    end
  end

  def tick(mob, blackboard, _context), do: {:failure, mob, blackboard}

  defp clear(mob, blackboard) do
    blackboard = Blackboard.clear_flee(blackboard)
    mob = %{mob | internal: %{mob.internal | blackboard: blackboard, broadcast_update?: true}}
    {:failure, ControlMovement.sync_flags(mob), blackboard}
  end

  defp move(mob, blackboard, %Context{now: now, perception: perception, random: random} = context) do
    {x, y, z, _orientation} = mob.movement_block.position
    source = blackboard.combat.flee_from || mob.unit.target

    angle =
      case Perception.position(perception, source) do
        {world, sx, sy, _sz} when world == mob.internal.world ->
          :math.atan2(y - sy, x - sx) + (Random.float(random) - 0.5) * :math.pi() / 2.0

        _ ->
          Random.float(random) * 2.0 * :math.pi()
      end

    distance = 12.0 + Random.float(random) * 8.0
    destination = {x + :math.cos(angle) * distance, y + :math.sin(angle) * distance, z}
    mob = %{mob | internal: %{mob.internal | running: true}}
    mob = Navigation.move_to(mob, destination, [allow_steep: false, max_distance: 30.0], context)
    {BT.running(min(1_500, blackboard.combat.flee_until - now), :flee), mob, blackboard}
  end
end
