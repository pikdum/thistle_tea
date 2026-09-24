defmodule ThistleTea.Game.World.OutdoorPvp.CaptureRewards do
  @moduledoc "Owns the spawned services and reinforcements supplied by captured towers."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.OutdoorPvp.PlaguelandsRewards
  alias ThistleTea.Game.OutdoorPvp.PlaguelandsRewards.Spawn
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Graveyards
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.WorldRef

  require Logger

  def reconcile(existing, towers) do
    desired = PlaguelandsRewards.spawns(towers)
    retired = Map.reject(existing, fn {key, {spec, _guid}} -> desired[key] == spec end)
    stop(retired)
    retained = Map.drop(existing, Map.keys(retired))

    created =
      desired
      |> Map.drop(Map.keys(retained))
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {key, spec}, created ->
        case start(spec) do
          {:ok, guid} -> Map.put(created, key, {spec, guid})
          _failed -> created
        end
      end)

    connect_squad(Map.merge(retained, created), Map.keys(created))
    Graveyards.control(927, faction(PlaguelandsRewards.graveyard_owner(towers)))
    Map.merge(retained, created)
  end

  def stop(objects) do
    Enum.each(objects, fn {_key, {_spec, guid}} -> World.stop_entity(guid) end)
  end

  defp start(%Spawn{} = spec) do
    entity = build(spec)

    with {:ok, pid} <- World.start_entity(entity) do
      start_waypoints(pid, entity.object.guid, spec.waypoint_entry)
      {:ok, entity.object.guid}
    end
  rescue
    error ->
      Logger.error("Tower reward #{spec.entry} failed: #{Exception.message(error)}")
      {:error, :unavailable}
  end

  defp build(%Spawn{kind: :game_object, entry: entry, position: position}) do
    %GameObjectTemplate{} = template = TemplateLoader.cached(entry)
    GameObject.build_summoned(template, WorldRef.open(0), position)
  end

  defp build(%Spawn{kind: :mob} = spec) do
    mob = Summon.build(spec.entry, WorldRef.open(0), spec.position)
    mob = if spec.faction, do: %{mob | unit: %{mob.unit | faction_template: spec.faction}}, else: mob

    if spec.aura do
      spell = SpellLoader.cached(spec.aura)
      {mob, _effects} = Aura.apply_spell(mob, mob.object.guid, mob.unit.level, spell, Time.now())
      mob
    else
      mob
    end
  end

  defp start_waypoints(_pid, _guid, nil), do: :ok

  defp start_waypoints(pid, guid, entry) do
    step = %ScriptStep{command: :start_waypoints, datalong: 3, dataint2: entry, datalong3: 1000}
    GenServer.cast(pid, {:start_script, [step], guid})
  end

  defp connect_squad(objects, created_keys) do
    case objects[{:eastwall, 0}] do
      {%Spawn{position: {x, y, _z, _o}}, leader} ->
        objects |> Map.take(created_keys) |> Enum.each(&connect_soldier(&1, leader, {x, y}))

      nil ->
        :ok
    end
  end

  defp connect_soldier({{:eastwall, index}, {%Spawn{position: {x, y, _z, o}}, guid}}, leader, {lx, ly})
       when index in 1..4 do
    angle = :math.atan2(y - ly, x - lx) - o
    step = %ScriptStep{command: :join_creature_group, datalong: 0x07, position: {5.0, 0.0, 0.0, angle}}
    GenServer.cast(Entity.pid(guid), {:start_script, [step], leader})
  end

  defp connect_soldier(_object, _leader, _position), do: :ok
  defp faction(:alliance), do: 469
  defp faction(:horde), do: 67
  defp faction(nil), do: nil
end
