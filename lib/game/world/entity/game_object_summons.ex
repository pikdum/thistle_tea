defmodule ThistleTea.Game.World.Entity.GameObjectSummons do
  @moduledoc """
  Creates spell-owned and independent world objects. The owning unit or
  object retains monitor records for slot replacement and world departure;
  each owned object also monitors that exact owner process, so a script's
  objects go when the object that raised them does.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Commands
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Ritual
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Pathfinding

  require Logger

  defmodule Entry do
    @moduledoc false
    @enforce_keys [:guid, :pid]
    defstruct [:guid, :pid, :slot]
  end

  def prepare(%{internal: %Internal{world: world}, movement_block: %{position: source}} = entity, effect) do
    %{effect | world: world, position: position(effect, source), cooldown_event: cooldown_event(entity, effect)}
  end

  def summon(
        %{internal: %Internal{world: world}} = entity,
        monitors,
        %Effects.SummonGameObject{world: world} = effect,
        context
      ) do
    monitors = replace_slot(monitors, effect.slot)

    case start(entity, effect, context) do
      {:ok, game_object, pid} ->
        token = Process.monitor(pid, tag: :game_object_down)
        Map.put(monitors, token, %Entry{guid: game_object.object.guid, pid: pid, slot: effect.slot})

      :error ->
        monitors
    end
  end

  def summon(_entity, monitors, effect, context) do
    cancel_cooldown(effect.cooldown_event, context)
    monitors
  end

  def dismiss(entity, monitors) do
    entity = Enum.reduce(monitors, entity, &release/2)
    {entity, %{}}
  end

  def start(%{object: %{guid: owner_guid}, internal: %Internal{world: world}} = entity, effect, context) do
    case GameObjectTemplateLoader.cached(effect.entry) do
      %GameObjectTemplate{} = template ->
        options = [
          summoned_by: if(effect.owned?, do: owner_guid),
          owner_pid: if(effect.owned?, do: owner_pid(context)),
          level: if(effect.owned?, do: owner_level(entity), else: 0),
          despawn_in_ms: effect.duration_ms,
          ritual_target_guid: effect.target_guid,
          ritual_zone_id: zone_id(world, effect.position)
        ]

        game_object = GameObject.build_summoned(template, world, effect.position, options)
        linked = linked_objects(template, world, effect.position, options)
        summon = %{game_object.internal.summon | linked_guids: linked, cooldown_event: effect.cooldown_event}
        game_object = %{game_object | internal: %{game_object.internal | summon: summon}}
        start_object(game_object, context)

      _missing ->
        cancel_cooldown(effect.cooldown_event, context)
        :error
    end
  end

  defp replace_slot(monitors, slot) when slot in 1..4 do
    Map.reject(monitors, fn
      {_token, %Entry{slot: ^slot}} = entry ->
        stop(entry)
        true

      _entry ->
        false
    end)
  end

  defp replace_slot(monitors, _slot), do: monitors

  defp stop({token, %Entry{pid: pid}}) do
    Process.demonitor(token, [:flush])
    release_object(pid)
  end

  defp release({token, %Entry{pid: pid}}, entity) do
    Process.demonitor(token, [:flush])

    case release_object(pid) do
      %Effects.ActivateCooldown{} = event when not is_nil(entity) ->
        {entity, effects} = Cooldowns.handle_event(entity, event, Time.now())
        Effects.enqueue(entity, effects)

      _ ->
        entity
    end
  end

  defp release_object(pid) do
    GenServer.call(pid, :release_summon)
  catch
    :exit, _reason -> nil
  end

  defp start_object(game_object, context) do
    case World.start_incarnation(game_object) do
      {:ok, pid} ->
        track_channel(game_object, context)
        {:ok, game_object, pid}

      failure ->
        Logger.warning("Summoned object #{game_object.object.entry} failed to start: #{inspect(failure, limit: 5)}")
        Enum.each(game_object.internal.summon.linked_guids, &World.stop_entity/1)
        cancel_cooldown(game_object.internal.summon.cooldown_event, context)
        :error
    end
  end

  defp linked_objects(template, world, position, options) do
    with entry when is_integer(entry) and entry > 0 <- GameObjectTemplate.linked_entry(template),
         %GameObjectTemplate{} = linked <- GameObjectTemplateLoader.cached(entry),
         game_object = GameObject.build_summoned(linked, world, position, options),
         {:ok, _pid} <- World.start_incarnation(game_object) do
      [game_object.object.guid]
    else
      _missing -> []
    end
  end

  defp position(%Effects.SummonGameObject{position: nil}, source), do: source

  defp position(%Effects.SummonGameObject{position: {x, y, z, orientation}}, {sx, sy, sz, so}) do
    {coordinate(x, sx), coordinate(y, sy), coordinate(z, sz), coordinate(orientation, so)}
  end

  defp coordinate(value, _fallback) when is_number(value), do: value
  defp coordinate(_value, fallback), do: fallback

  defp track_channel(
         %GameObject{object: %{guid: guid}, internal: %Internal{ritual: %Ritual{owner_guid: owner_guid}}},
         context
       )
       when is_integer(owner_guid) do
    Context.send(context, %Commands.ChannelGameObjectStarted{guid: guid})
  end

  defp track_channel(%GameObject{}, _context), do: :ok

  defp owner_pid(%Context{owner_pid: pid}), do: pid
  defp owner_pid(_context), do: nil

  defp owner_level(%{unit: %{level: level}}) when is_integer(level), do: level
  defp owner_level(%GameObject{game_object: %{level: level}}) when is_integer(level) and level > 0, do: level
  defp owner_level(_entity), do: 1

  defp zone_id(%{map_id: map_id}, {x, y, z, _orientation}) do
    case Pathfinding.get_zone_and_area(map_id, {x, y, z}) do
      {zone_id, _area_id} -> zone_id
      _missing -> 0
    end
  end

  defp cooldown_event(entity, %Effects.SummonGameObject{owned?: true, spell_id: spell_id}) do
    case Cooldowns.pending(entity, spell_id) do
      nil ->
        nil

      entry ->
        %Effects.ActivateCooldown{target_guid: entity.object.guid, spell_id: spell_id, started_at: entry.started_at}
    end
  end

  defp cooldown_event(_entity, _effect), do: nil

  defp cancel_cooldown(nil, _context), do: :ok
  defp cancel_cooldown(event, context), do: Context.send(context, %{event | cancel?: true})
end
