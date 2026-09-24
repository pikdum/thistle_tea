defmodule ThistleTea.Game.World.OutdoorPvp.CaptureEnvironment do
  @moduledoc "Collects current capture participants and manages region-owned banner processes."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.OutdoorPvp.Towers.Participant
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  def templates do
    Map.new(Plaguelands.towers(), fn {_id, definition} ->
      %Template{} = template = Template.from_game_object(TemplateLoader.cached(definition.entry))
      {definition.entry, template}
    end)
  end

  def participants(members) do
    Enum.flat_map(members, fn {guid, member} ->
      with true <- member.zone == 139,
           true <- Entity.pid(guid) == member.pid,
           %{outdoor_pvp_eligible?: true} <- Metadata.get(guid),
           {world, x, y, z} <- World.position(guid) do
        [%Participant{guid: guid, team: member.team, world: world, position: {x, y, z}, eligible?: true}]
      else
        _unavailable -> []
      end
    end)
  end

  def spawn_banners do
    Map.new(Plaguelands.towers(), fn {id, definition} ->
      capture = spawn_object(definition.entry, definition.position, definition.rotation)
      banners = Enum.map(definition.banners, &spawn_object(182_106, &1, nil))
      {id, [capture | banners]}
    end)
  end

  def update_banners(objects, id, owner) do
    Enum.each(Map.get(objects, id, []), fn guid ->
      case Entity.pid(guid) do
        pid when is_pid(pid) ->
          GenServer.cast(pid, {:set_art_kit, Plaguelands.art_kit(owner), Plaguelands.animation(owner)})

        _missing ->
          :ok
      end
    end)
  end

  def stop_banners(objects) do
    objects |> Map.values() |> List.flatten() |> Enum.each(&World.stop_entity/1)
  end

  defp spawn_object(entry, position, rotation) do
    %GameObjectTemplate{} = template = TemplateLoader.cached(entry)
    entity = GameObject.build_summoned(template, WorldRef.open(0), position)
    object = %{entity.game_object | art_kit: Plaguelands.art_kit(nil)}
    object = rotate(object, rotation)
    entity = %{entity | game_object: object}
    {:ok, _pid} = World.start_entity(entity)
    entity.object.guid
  end

  defp rotate(object, nil), do: object
  defp rotate(object, {r0, r1, r2, r3}), do: %{object | rotation0: r0, rotation1: r1, rotation2: r2, rotation3: r3}
end
