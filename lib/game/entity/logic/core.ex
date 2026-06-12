defmodule ThistleTea.Game.Entity.Logic.Core do
  @moduledoc """
  Entity operations generic across all entity types: building update-object
  payloads, taking damage and dying, healing, mana restoration, and combat
  tether-range checks for mobs.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.DynamicObject, as: DataDynamicObject
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network.UpdateObject

  @leash_timeout_ms 6_000

  def update_object(entity, update_type \\ :create_object2)
  def update_object(%Mob{} = entity, update_type), do: update_object(entity, update_type, :unit)
  def update_object(%GameObject{} = entity, update_type), do: update_object(entity, update_type, :game_object)
  def update_object(%Corpse{} = entity, update_type), do: update_object(entity, update_type, :corpse)

  def update_object(%DataDynamicObject{} = entity, update_type), do: update_object(entity, update_type, :dynamic_object)
  def update_object(%Character{} = entity, update_type), do: update_object(entity, update_type, :player)

  def update_object(entity, update_type, object_type) do
    %UpdateObject{
      update_type: update_type,
      object_type: object_type
    }
    |> struct(Map.from_struct(entity))
  end

  def take_damage(entity, damage, now, opts \\ [])

  def take_damage(%{internal: %Internal{godmode: true}} = entity, _damage, _now, _opts), do: entity

  def take_damage(%{unit: %Unit{health: health}} = entity, damage, now, opts) when is_integer(now) do
    {entity, damage} = Aura.absorb_damage(entity, damage, Keyword.get(opts, :school, :physical))
    %{unit: unit} = entity
    new_health = max(health - damage, 0)

    entity = %{entity | unit: %{unit | health: new_health}}
    entity = if damage > 0, do: Aura.break_on_damage(entity, now), else: entity

    entity
    |> mark_broadcast_update()
    |> maybe_dead(now)
  end

  def heal(%{unit: %Unit{health: health, max_health: max_health} = unit} = entity, amount)
      when is_number(health) and is_number(amount) and amount > 0 do
    new_health =
      if is_number(max_health) and max_health > 0 do
        min(health + amount, max_health)
      else
        health + amount
      end

    %{entity | unit: %{unit | health: new_health}}
    |> mark_broadcast_update()
  end

  def heal(entity, _amount), do: entity

  def restore_mana(%{unit: %Unit{power1: power, max_power1: max_power} = unit} = entity, amount)
      when is_number(power) and is_number(max_power) and max_power > 0 and is_number(amount) and amount > 0 do
    %{entity | unit: %{unit | power1: min(power + amount, max_power)}}
    |> mark_broadcast_update()
  end

  def restore_mana(entity, _amount), do: entity

  def dead?(%{unit: %Unit{health: health}}) when is_number(health) do
    health <= 0
  end

  def dead?(_entity), do: false

  def mark_broadcast_update(%{internal: %Internal{} = internal} = entity) do
    %{entity | internal: %{internal | broadcast_update?: true}}
  end

  def mark_broadcast_update(entity), do: entity

  def tether_range(%{unit: %Unit{level: level}}) when is_number(level) do
    40 + 2 * level
  end

  def tether_range(_entity) do
    nil
  end

  def out_of_tether_range?(
        %{internal: %Internal{initial_position: {xi, yi, zi}}, movement_block: %MovementBlock{position: {x, y, z, _}}} =
          entity
      ) do
    case tether_range(entity) do
      range when is_number(range) ->
        Math.distance({xi, yi, zi}, {x, y, z}) > range

      _ ->
        false
    end
  end

  def out_of_tether_range?(_entity) do
    false
  end

  def should_tether?(%{internal: %Internal{last_hostile_time: last_hostile_time}} = entity, now)
      when is_integer(last_hostile_time) and is_integer(now) do
    out_of_tether_range?(entity) and now - last_hostile_time >= @leash_timeout_ms
  end

  def should_tether?(_entity, _now) do
    false
  end

  defp maybe_dead(%{internal: %Internal{}, unit: %Unit{health: 0}, movement_block: %MovementBlock{}} = entity, now) do
    entity = Movement.sync_position(entity, now)
    %{internal: internal, unit: unit, movement_block: mb} = entity

    unit =
      %{unit | target: 0, auras: []}
      |> Aura.sync_unit()

    internal = %{
      internal
      | in_combat: false,
        running: false,
        movement_start_time: nil,
        movement_start_position: nil
    }

    movement_block = %{
      mb
      | movement_flags: 0,
        spline_nodes: [],
        spline_flags: 0,
        spline_id: nil,
        spline_start_position: nil,
        time_passed: mb.duration || 0
    }

    %{entity | unit: unit, internal: internal, movement_block: movement_block}
  end

  defp maybe_dead(entity, _now), do: entity
end
