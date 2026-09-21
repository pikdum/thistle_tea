defmodule ThistleTea.Game.Entity.Logic.Fear do
  @moduledoc """
  Fear readiness and destination selection. Fear runs start
  at the entity's current position, with distances based on the frightening
  caster's proximity, rather than returning to a confusion anchor.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math

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

  def blocked?(%{unit: %Unit{health: health, auras: holders}, internal: %Internal{} = internal}) do
    health <= 0 or internal.rooted? or
      Enum.any?(holders, &Holder.has_any_type?(&1, [:mod_root, :mod_stun, :mod_confuse]))
  end

  def ready?(%{unit: %Unit{}, internal: %Internal{} = internal} = mob, now) do
    memory = Blackboard.ensure(internal.blackboard).fear

    active?(mob) and not blocked?(mob) and not Movement.moving?(mob, now) and
      (is_nil(memory) or (not memory.moving? and now >= memory.next_move_at))
  end

  def ready?(_entity, _now), do: false

  def destination_request(%{unit: %Unit{}, internal: %Internal{}} = mob, %Perception{} = perception, %Random{} = random) do
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

  defp holder(holders) do
    if !Enum.any?(holders, &Holder.has_aura_type?(&1, :prevent_fleeing)) do
      Enum.find(holders, &Holder.has_aura_type?(&1, :mod_fear))
    end
  end
end
