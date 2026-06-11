defmodule ThistleTea.Game.Entity.Server.DynamicObject do
  @moduledoc """
  Owning GenServer for an area-effect dynamic object: runs its periodic damage
  ticks and despawns itself when the effect expires (`restart: :temporary` so
  the supervisor doesn't resurrect it).
  """
  use GenServer, restart: :temporary

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.DynamicObject
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Visibility

  require Logger

  def start_link(%{entity: %DynamicObject{} = entity} = opts) do
    GenServer.start_link(__MODULE__, opts, name: EntityRegistry.via(entity.object.guid))
  end

  @impl GenServer
  def init(%{entity: %DynamicObject{} = entity} = opts) do
    Process.flag(:trap_exit, true)

    World.update_position(entity)
    entity = Visibility.join_entity(entity)

    state =
      opts
      |> Map.put(:entity, entity)
      |> Map.put(:expires_at, Time.now() + opts.duration_ms)

    Process.send_after(self(), :expire, opts.duration_ms)

    if is_map(state[:tick]) do
      send(self(), :tick)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, %{entity: entity} = state) do
    Core.update_object(entity)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:tick, %{entity: entity, tick: tick} = state) do
    now = Time.now()

    if now < state.expires_at do
      apply_tick(entity, tick)
      Process.send_after(self(), :tick, tick.interval_ms)
    end

    {:noreply, state}
  rescue
    error ->
      Logger.error("DynamicObject tick failed: #{inspect(error)}")
      {:noreply, state}
  end

  def handle_info(:expire, state) do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{entity: entity}) do
    World.remove_position(entity)
    Visibility.leave_entity(entity)
  end

  defp apply_tick(%DynamicObject{} = entity, tick) do
    %{caster: caster, spell: spell, effect: effect} = tick
    {x, y, z, _o} = entity.movement_block.position
    radius = entity.dynamic_object.radius

    tick_spell = %{spell | cast_time_ms: 0, effects: [%{effect | type: :school_damage, aura: nil}]}

    caster
    |> SpellTargetResolver.resolve_query({:targeted_aoe, {x, y, z}, radius})
    |> Enum.each(fn target_guid ->
      context = %CastContext{
        caster_guid: caster.object.guid,
        caster_level: caster_level(caster),
        target_guid: target_guid,
        spell: tick_spell
      }

      Entity.receive_spell(target_guid, context, tick_spell)
    end)
  end

  defp caster_level(%{unit: %{level: level}}) when is_integer(level), do: level
  defp caster_level(_caster), do: 1

  def tick_config(caster, %Spell{} = spell, %Effect{} = effect) do
    %{
      caster: caster,
      spell: spell,
      effect: effect,
      interval_ms: tick_interval(effect)
    }
  end

  defp tick_interval(%Effect{amplitude_ms: amp}) when is_integer(amp) and amp > 0, do: amp
  defp tick_interval(_effect), do: 1_000
end
