defmodule ThistleTea.Game.World.InstanceSpawn do
  @moduledoc """
  Materializes a database spawn blueprint inside one world copy.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  def materialize(%Mob{} = mob, %WorldRef{} = world) do
    old_guid = mob.object.guid
    guid = runtime_guid(world, :mob, mob.object.entry, old_guid)
    unit = replace_aura_source(mob.unit, old_guid, guid)
    internal = materialize_internal(mob.internal, world, old_guid, guid)
    %{mob | object: %{mob.object | guid: guid}, unit: unit, internal: internal}
  end

  def materialize(%GameObject{} = game_object, %WorldRef{} = world) do
    guid = runtime_guid(world, :game_object, game_object.object.entry, game_object.object.guid)
    %{game_object | object: %{game_object.object | guid: guid}, internal: %{game_object.internal | world: world}}
  end

  defp runtime_guid(%WorldRef{instance_id: nil}, _type, _entry, guid), do: guid
  defp runtime_guid(%WorldRef{}, type, entry, _guid), do: Guid.runtime(type, entry)

  defp materialize_internal(%Internal{spawn: %Spawn{} = spawn} = internal, world, old_guid, guid) do
    spawn = %{spawn | unit: replace_aura_source(spawn.unit, old_guid, guid)}
    %{internal | world: world, spawn: spawn}
  end

  defp materialize_internal(%Internal{} = internal, world, _old_guid, _guid) do
    %{internal | world: world}
  end

  defp replace_aura_source(%{auras: auras} = unit, old_guid, guid) when is_list(auras) do
    auras =
      Enum.map(auras, fn
        %Holder{caster_guid: ^old_guid} = holder -> %{holder | caster_guid: guid}
        %Holder{} = holder -> holder
      end)

    %{unit | auras: auras}
  end

  defp replace_aura_source(unit, _old_guid, _guid), do: unit
end
