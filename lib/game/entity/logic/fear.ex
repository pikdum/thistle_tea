defmodule ThistleTea.Game.Entity.Logic.Fear do
  @moduledoc """
  Creature fear movement lifecycle and destination selection. Fear runs start
  at the creature's current position, with distances based on the frightening
  caster's proximity, rather than returning to a confusion anchor.
  """

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Fear, as: FearMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math

  @fleeing_flag 0x00800000
  @search_radius 5.0

  def source_guid(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    case holder(holders) do
      %Holder{caster_guid: guid} -> guid
      nil -> nil
    end
  end

  def source_guid(_entity), do: nil

  def active?(%{unit: %Unit{auras: holders}}) when is_list(holders), do: holder(holders) != nil
  def active?(_entity), do: false

  def blocked?(%Mob{unit: %Unit{health: health, auras: holders}, internal: internal}) do
    health <= 0 or internal.rooted? or
      Enum.any?(holders, &Holder.has_any_type?(&1, [:mod_root, :mod_stun, :mod_confuse]))
  end

  def ready?(%Mob{internal: internal} = mob, now) do
    memory = Blackboard.ensure(internal.blackboard).fear

    active?(mob) and not blocked?(mob) and not Movement.moving?(mob, now) and
      (is_nil(memory) or (not memory.moving? and now >= memory.next_move_at))
  end

  def ready?(_entity, _now), do: false

  def reconcile(%Mob{} = mob, previous, current, now) do
    active? = holder(current) != nil
    flags = (mob.unit.flags || 0) &&& bnot(@fleeing_flag)
    flags = if active?, do: flags ||| @fleeing_flag, else: flags
    mob = %{mob | unit: %{mob.unit | flags: flags}}

    if key(previous) == key(current) do
      {mob, []}
    else
      blackboard = Blackboard.ensure(mob.internal.blackboard)
      running = if blackboard.fear, do: blackboard.fear.previous_running, else: mob.internal.running
      memory = if active?, do: %FearMemory{next_move_at: now, previous_running: running}
      blackboard = %{Blackboard.clear_move_target(blackboard) | fear: memory}
      {mob, events} = Movement.stop_with_effects(mob, now)
      internal = %{mob.internal | blackboard: blackboard, running: running, navigation_intents: []}
      {%{mob | internal: internal}, events}
    end
  end

  def reconcile(entity, _previous, _current, _now), do: {entity, []}

  def destination_request(%Mob{} = mob, %Perception{} = perception, %Random{} = random) do
    {x, y, z, _orientation} = mob.movement_block.position
    distance = caster_distance(mob, perception, {x, y, z})
    angle = Random.float(random) * 2 * :math.pi()
    roll = Random.float(random)

    length =
      cond do
        distance < 28.0 -> (0.4 + roll * 0.9) * (28.0 - distance)
        distance > 38.0 -> (0.4 + roll * 0.6) * 10.0
        true -> (0.6 + roll * 0.6) * 10.0
      end

    length = min(length, 30.0 - @search_radius)
    {mob.internal.world.map_id, {x + :math.cos(angle) * length, y + :math.sin(angle) * length, z}, @search_radius}
  end

  defp caster_distance(mob, perception, position) do
    case Perception.position(perception, source_guid(mob)) do
      {world, x, y, z} when world == mob.internal.world -> Math.distance(position, {x, y, z})
      _ -> 0.0
    end
  end

  defp holder(holders), do: Enum.find(holders, &Holder.has_aura_type?(&1, :mod_fear))

  defp key(holders) do
    case holder(holders) do
      %Holder{spell: spell, caster_guid: caster_guid, applied_at: applied_at} -> {spell.id, caster_guid, applied_at}
      nil -> nil
    end
  end
end
