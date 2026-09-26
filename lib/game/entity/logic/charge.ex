defmodule ThistleTea.Game.Entity.Logic.Charge do
  @moduledoc """
  Finite charge movement shared by player and creature owners. Roots and stuns
  acquired in flight take effect when the charge ends or is interrupted.
  """

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura.MovementSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell

  @enforce_keys [:arrives_at, :spline_id]
  defstruct [:arrives_at, :spline_id, :attack_target]

  def attack_on_arrival?(%Spell{} = spell) do
    Spell.harmful?(spell) and not Spell.attribute?(spell, :cancels_auto_attack_combat)
  end

  def approach_path([], _origin, _target, _reach), do: []

  def approach_path([point | rest], {x, y, z} = origin, {tx, ty, tz} = target, reach) do
    if Math.distance(point, target) <= reach do
      distance = Math.distance(origin, target)

      if distance <= reach do
        []
      else
        fraction = (distance - reach) / distance
        [{x + (tx - x) * fraction, y + (ty - y) * fraction, z + (tz - z) * fraction}]
      end
    else
      [point | approach_path(rest, point, target, reach)]
    end
  end

  def start(entity, %Commands.ChargePathResolved{} = command) do
    if Core.dead?(entity) or Movement.blocked?(entity) or not is_nil(entity.internal.taxi_flight),
      do: entity,
      else: begin_charge(entity, command)
  end

  defp begin_charge(entity, command) do
    entity = Movement.start_timed_path(entity, command.path, command.duration_ms, command.started_at, run?: true)

    charge = %__MODULE__{
      arrives_at: command.started_at + command.duration_ms,
      spline_id: entity.internal.spline_id,
      attack_target: command.attack_target
    }

    %{entity | internal: %{entity.internal | charge: charge}}
    |> delay_swings(command.swing_delay_ms, command.started_at)
    |> Effects.enqueue(Effects.monster_move())
  end

  defp delay_swings(%Character{} = entity, delay, now) when delay > 0 do
    blackboard = Blackboard.ensure(entity.internal.blackboard)

    blackboard =
      Enum.reduce([:next_attack_at, :next_offhand_attack_at], blackboard, fn key, acc ->
        Blackboard.put_next_at(acc, key, Blackboard.delay_until(acc, key, now) + delay, now)
      end)

    %{entity | internal: %{entity.internal | blackboard: blackboard}}
  end

  defp delay_swings(entity, _delay, _now), do: entity

  def active?(%{internal: %Internal{charge: %__MODULE__{spline_id: id}, spline_id: id}} = entity, now) do
    not Core.dead?(entity) and Movement.moving?(entity, now)
  end

  def active?(_entity, _now), do: false

  def reconcile(%{internal: %Internal{charge: %__MODULE__{arrives_at: at}}} = entity, now) do
    if now >= at or not active?(entity, now), do: finish(entity, now), else: entity
  end

  def reconcile(entity, _now), do: entity

  def finish(%{internal: %Internal{charge: %__MODULE__{spline_id: id} = charge, spline_id: id}} = entity, now) do
    entity |> Movement.finish(now) |> clear() |> sync_roots(now) |> start_attack(charge, now)
  end

  def finish(%{internal: %Internal{charge: %__MODULE__{}}} = entity, now), do: release(entity, now)

  def finish(entity, _now), do: entity

  def cancel(%{internal: %Internal{charge: %__MODULE__{}}} = entity, now) do
    entity |> Movement.stop(now) |> clear() |> sync_roots(now)
  end

  def cancel(entity, now), do: Movement.stop(entity, now)

  def release(%{internal: %Internal{charge: %__MODULE__{}}} = entity, now), do: entity |> clear() |> sync_roots(now)

  def release(entity, _now), do: entity

  defp clear(entity), do: %{entity | internal: %{entity.internal | charge: nil}}

  defp start_attack(entity, %__MODULE__{attack_target: %TargetRef{} = target, arrives_at: at}, now) when now >= at do
    if Core.dead?(entity), do: entity, else: Effects.enqueue(entity, Effects.attack_start(target))
  end

  defp start_attack(entity, _charge, _now), do: entity

  defp sync_roots(entity, now) do
    {entity, events} = MovementSync.sync_movement_state(entity, now)
    Effects.enqueue(entity, events)
  end
end
