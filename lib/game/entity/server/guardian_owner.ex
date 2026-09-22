defmodule ThistleTea.Game.Entity.Server.GuardianOwner do
  @moduledoc """
  Unit-owner boundary for spawning, monitoring, and releasing autonomous guardians.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Guardians
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Guardian, as: GuardianLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Pathfinding

  def summon(entity, monitors, %Effects.SummonGuardians{} = effect) do
    {prepared, summon?} = Guardians.prepare(entity, effect)
    now = Time.now()

    guardians =
      if summon? do
        Enum.map(0..(effect.count - 1), fn index ->
          position = position(prepared, effect, index)
          GuardianLoader.build(prepared, effect, position, now, index)
        end)
      else
        []
      end

    monitors = release_removed(monitors, prepared)
    prepared = EventSink.emit_pending(prepared)

    Enum.reduce(guardians, {prepared, monitors}, fn guardian, {owner, monitors} ->
      case MobLoader.start_mob(guardian) do
        {:ok, pid} ->
          ref = %EntityRef{guid: guardian.object.guid, entry: effect.entry, spell_id: effect.spell_id}
          token = Process.monitor(pid)
          update_owner(owner, ref.guid)
          {Guardians.activate(owner, ref), Map.put(monitors, token, ref.guid)}

        _failed ->
          {owner, monitors}
      end
    end)
  end

  def dismiss(entity, monitors) do
    Enum.each(monitors, fn {token, _guid} -> Process.demonitor(token, [:flush]) end)
    {entity |> Guardians.dismiss_all() |> EventSink.emit_pending(), %{}}
  end

  def owner_stopped(entity) do
    case Guardians.active(entity) do
      [] -> :ok
      guardians -> Task.start(fn -> Enum.each(guardians, &World.stop_entity(&1.guid)) end)
    end
  end

  def process_down(entity, monitors, token) do
    case Map.pop(monitors, token) do
      {nil, _monitors} -> {entity, monitors}
      {guid, monitors} -> {Guardians.removed(entity, guid), monitors}
    end
  end

  def defend(entity, attacker_guid) when is_integer(attacker_guid) do
    Enum.each(Guardians.active(entity), fn %EntityRef{guid: guid} ->
      case Entity.pid(guid) do
        pid when is_pid(pid) -> send(pid, {:owner_attacked, attacker_guid})
        _ -> :ok
      end
    end)
  end

  def defend(_entity, _attacker_guid), do: :ok

  defp update_owner(%Character{object: %{guid: owner_guid}}, guid), do: Entity.request_update_from(guid, owner_guid)

  defp update_owner(_owner, _guid), do: :ok

  defp release_removed(monitors, entity) do
    Map.filter(monitors, fn {token, guid} ->
      if Map.has_key?(entity.internal.guardians, guid) do
        true
      else
        Process.demonitor(token, [:flush])
        false
      end
    end)
  end

  defp position(entity, %Effects.SummonGuardians{position: nil}, _index), do: entity.movement_block.position

  defp position(entity, %Effects.SummonGuardians{position: {x, y, z, orientation}, radius_yards: radius}, index)
       when index > 0 and radius > 0 do
    case Pathfinding.find_random_point_around_circle(entity.internal.world.map_id, {x, y, z}, radius) do
      {px, py, pz} -> {px, py, pz, orientation}
      _ -> {x, y, z, orientation}
    end
  end

  defp position(_entity, effect, _index), do: effect.position
end
