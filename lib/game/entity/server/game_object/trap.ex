defmodule ThistleTea.Game.Entity.Server.GameObject.Trap do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Component.Internal.Trap
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  def publish_range(%GameObject{internal: %{trap: %Trap{spell_id: spell_id}}} = object) do
    range =
      case SpellLoader.cached(spell_id) do
        %Spell{range_yards: range} when is_number(range) -> range
        _ -> 0.5
      end

    Metadata.update(object.object.guid, %{go_trap_range: Focus.range(range, nil)})
  end

  def linked_guid(%GameObject{} = object) do
    case TemplateLoader.cached(object.object.entry) do
      %GameObjectTemplate{} = template -> find_linked(object, GameObjectTemplate.linked_entry(template))
      _ -> nil
    end
  end

  defp find_linked(_object, 0), do: nil

  defp find_linked(object, entry) do
    object.internal.world
    |> World.game_objects_in()
    |> Enum.filter(&(Guid.entry(&1) == entry))
    |> Enum.flat_map(fn guid ->
      with %{go_spawned?: true, go_trap_range: range} <- Metadata.get(guid),
           distance when is_number(distance) and distance < range <- World.distance_between(object, guid) do
        [{distance, guid}]
      else
        _ -> []
      end
    end)
    |> Enum.min(fn -> nil end)
    |> case do
      {_distance, guid} -> guid
      nil -> nil
    end
  end

  def target(%GameObject{internal: %{trap: %Trap{radius: radius}}}) when not is_number(radius) or radius <= 0, do: nil

  def target(%GameObject{
        internal: %{world: world, trap: %Trap{owner_guid: nil, radius: radius}},
        movement_block: %{position: {x, y, z, _o}}
      }) do
    :players
    |> World.nearby_units_exact(world, {x, y, z}, radius)
    |> Enum.map(&elem(&1, 0))
    |> Enum.find(&match?(%{alive?: true}, Metadata.query(&1, [:alive?])))
  end

  def target(%GameObject{
        internal: %{world: world, trap: %Trap{owner_guid: owner_guid, radius: radius}},
        movement_block: %{position: {x, y, z, _o}}
      }) do
    source = %{object: %{guid: owner_guid}}

    ((:mobs |> World.nearby_units_exact(world, {x, y, z}, radius)) ++
       (:players |> World.nearby_units_exact(world, {x, y, z}, radius)))
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 == owner_guid))
    |> Enum.find(&Hostility.valid_attack_target?(source, &1))
  end

  def target(_state), do: nil

  def consume(%Trap{charges: 1}), do: :depleted

  def consume(%Trap{charges: charges} = trap) when is_integer(charges) and charges > 1,
    do: %{trap | charges: charges - 1}

  def consume(%Trap{} = trap), do: trap

  def ready?(%Trap{depleted?: true}, _now), do: false
  def ready?(%Trap{ready_at: nil}, _now), do: true
  def ready?(%Trap{ready_at: ready_at}, now), do: now >= ready_at
end
