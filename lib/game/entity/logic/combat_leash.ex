defmodule ThistleTea.Game.Entity.Logic.CombatLeash do
  @moduledoc """
  Pure combat-leash transitions and threat-area checks. Assistance can share
  an extension clock while every creature retains its own combat origin.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Data.CombatLeash, as: State
  alias ThistleTea.Game.Entity.Data.CombatLeash.Ref
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  @timeout_ms 12_000
  @threat_radius 50.0
  @controlled_flags 0x00040000 ||| 0x00400000 ||| 0x00800000

  def enter(%Mob{internal: %{combat_leash: %State{active?: true}}} = entity, now, _source), do: extend(entity, now)

  def enter(%Mob{} = entity, now, source) do
    entity = Movement.sync_position(entity, now)
    previous = entity.internal.combat_leash || %State{}

    leash = %State{
      generation: previous.generation + 1,
      active?: true,
      origin: current_position(entity),
      last_extended_at: if(!is_struct(source, Ref), do: now),
      next_control_at: now
    }

    entity = %{entity | internal: %{entity.internal | combat_leash: leash}}
    enqueue(entity, {:start, now, source})
  end

  def extend(%Mob{internal: %{combat_leash: %State{active?: true} = leash}} = entity, now) do
    if is_nil(leash.last_extended_at) or now > leash.last_extended_at do
      entity = %{entity | internal: %{entity.internal | combat_leash: %{leash | last_extended_at: now}}}
      enqueue(entity, {:extend, now})
    else
      entity
    end
  end

  def extend(entity, _now), do: entity

  def on_damage(%Mob{object: %{guid: guid}} = entity, now, opts) do
    case {Keyword.get(opts, :periodic), Keyword.get(opts, :spell), Keyword.get(opts, :source)} do
      {true, %Spell{} = spell, source} when is_integer(source) and source != guid ->
        if Spell.attribute?(spell, :channeled), do: extend(entity, now), else: entity

      _damage ->
        entity
    end
  end

  def on_damage(entity, _now, _opts), do: entity

  def stop(%Mob{internal: %{combat_leash: %State{active?: true} = leash}} = entity) do
    entity = enqueue(entity, :stop)
    leash = %State{generation: leash.generation}
    %{entity | internal: %{entity.internal | combat_leash: leash}}
  end

  def stop(entity), do: entity

  def reference(%Mob{internal: %{combat_leash: %State{active?: true, generation: generation}}} = entity) do
    spawn = entity.internal.spawn

    %Ref{
      world: entity.internal.world,
      guid: entity.object.guid,
      incarnation: spawn && spawn.incarnation_id,
      generation: generation
    }
  end

  def reference(_entity), do: nil

  def maintain(%Mob{internal: %{combat_leash: %State{active?: true} = leash}} = entity, now) do
    if controlled?(entity) and now >= leash.next_control_at do
      entity = extend(entity, now)
      leash = %{entity.internal.combat_leash | next_control_at: now + 3_000}
      %{entity | internal: %{entity.internal | combat_leash: leash}}
    else
      entity
    end
  end

  def maintain(entity, _now), do: entity

  def should_evade?(%{internal: internal, movement_block: %{position: {x, y, z, _}}} = entity, now, opts \\ []) do
    origin = origin(entity)
    hard_range = hard_range(entity)
    distance = if origin, do: Math.distance(origin, {x, y, z}), else: 0.0

    cond do
      is_number(hard_range) and distance > hard_range -> true
      not limited?(entity) -> false
      controlled?(entity) -> false
      distance <= max(@threat_radius, Keyword.get(opts, :attack_distance, 0.0) * 1.5) -> false
      victim_near?(origin, internal.world, opts) -> false
      true -> expired?(last_extended_at(entity, Keyword.get(opts, :shared_time)), now)
    end
  end

  def range(entity), do: hard_range(entity) || @threat_radius

  def origin(%{internal: %{combat_leash: %State{active?: true, origin: origin}}}), do: origin
  def origin(%{internal: %{spawn: %{position: position}}}), do: position
  def origin(_entity), do: nil

  defp current_position(%{movement_block: %{position: {x, y, z, _}}}), do: {x, y, z}
  defp current_position(_entity), do: nil

  defp last_extended_at(%{internal: %{combat_leash: %State{active?: true} = leash}} = entity, shared) do
    [leash.last_extended_at, shared]
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> entity.internal.last_hostile_time end)
  end

  defp last_extended_at(entity, _shared), do: entity.internal.last_hostile_time

  defp expired?(last, now) when is_integer(last), do: now - last > @timeout_ms
  defp expired?(_last, _now), do: false

  defp victim_near?(origin, world, opts) do
    case Keyword.get(opts, :victim_position) do
      {^world, x, y, z} when is_tuple(origin) ->
        Math.distance(origin, {x, y, z}) <= max(@threat_radius, Keyword.get(opts, :attack_distance, 0.0) * 1.5)

      _position ->
        false
    end
  end

  defp hard_range(%{internal: %{creature: %{leash_range: range}}}) when is_number(range) and range > 0, do: range
  defp hard_range(_entity), do: nil

  defp limited?(%{internal: %{world: %WorldRef{} = world}} = entity),
    do: WorldRef.open?(world) and not unlimited?(entity)

  defp limited?(entity), do: not unlimited?(entity)

  defp unlimited?(%{internal: %{creature: %{extra_flags: flags}}}) when is_integer(flags), do: (flags &&& 1) != 0
  defp unlimited?(_entity), do: false

  defp controlled?(%{internal: %{rooted?: true}}), do: true
  defp controlled?(%{unit: %{flags: flags}}) when is_integer(flags), do: (flags &&& @controlled_flags) != 0
  defp controlled?(_entity), do: false

  defp enqueue(entity, event),
    do: Effects.enqueue(entity, %Effects.CombatLeashEvent{ref: reference(entity), event: event})
end
