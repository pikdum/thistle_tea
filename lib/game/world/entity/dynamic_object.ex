defmodule ThistleTea.Game.World.Entity.DynamicObject do
  @moduledoc """
  Owning GenServer for an area-effect dynamic object: runs its periodic damage
  ticks and despawns itself when the effect expires (`restart: :temporary` so
  the supervisor doesn't resurrect it).
  """
  use GenServer, restart: :temporary

  alias ThistleTea.Game.Core.Aura.UnitSync
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.DynamicObject
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.PersistentArea
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.World.Spell.SpellTargetResolver
  alias ThistleTea.Game.World.Visibility

  require Logger

  def start_link(%{entity: %DynamicObject{} = entity} = opts) do
    GenServer.start_link(__MODULE__, opts, name: EntityRegistry.via(entity.object.guid))
  end

  def delay(pid, delay_ms) when is_pid(pid) and is_integer(delay_ms) and delay_ms > 0 do
    GenServer.cast(pid, {:delay, delay_ms})
  end

  @impl GenServer
  def init(%{entity: %DynamicObject{} = entity} = opts) do
    Process.flag(:trap_exit, true)
    AreaEffects.register(entity.dynamic_object.caster, entity.dynamic_object.spell_id)

    World.update_position(entity)
    entity = Visibility.join_entity(entity)

    now = Time.now()

    state =
      opts
      |> Map.put(:entity, entity)
      |> Map.put(:started_at, now)
      |> Map.put(:expires_at, now + opts.duration_ms)
      |> Map.put(:recipients, MapSet.new())
      |> schedule_expiry(now)

    if is_map(state[:tick]) do
      send(self(), :tick)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:delay, delay_ms}, state) when is_integer(delay_ms) and delay_ms > 0 do
    now = Time.now()
    expires_at = min(state.expires_at, max(now, state.expires_at - delay_ms))
    Process.cancel_timer(state.expiry_timer)
    state = schedule_expiry(%{state | expires_at: expires_at}, now)
    Enum.each(state.recipients, &Entity.shorten_area_aura(&1, state.entity.object.guid, expires_at))
    {:noreply, state}
  rescue
    error ->
      Logger.error("DynamicObject delay failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_cast({:send_update_to, pid}, %{entity: entity} = state) do
    EntityCore.update_object(entity)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:tick, %{tick: tick} = state) do
    now = Time.now()

    state =
      if now < state.expires_at do
        recipients = apply_tick(state)
        Process.send_after(self(), :tick, tick.interval_ms)
        %{state | recipients: MapSet.union(state.recipients, MapSet.new(recipients))}
      else
        state
      end

    {:noreply, state}
  rescue
    error ->
      Logger.error("DynamicObject tick crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      Process.send_after(self(), :tick, tick.interval_ms)
      {:noreply, state}
  end

  def handle_info({:expire, expires_at}, %{expires_at: expires_at} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{entity: entity, farsight_owner_guid: owner_guid}) do
    notify_farsight_owner(entity, owner_guid)
    World.remove_position(entity)
    Visibility.leave_entity(entity)
  end

  def terminate(_reason, %{entity: entity, recipients: recipients, expires_at: expires_at}) do
    if Time.now() < expires_at do
      Enum.each(recipients, &Entity.remove_area_aura(&1, entity.object.guid))
    end

    World.remove_position(entity)
    Visibility.leave_entity(entity)
  end

  defp notify_farsight_owner(%DynamicObject{object: %{guid: guid}}, owner_guid) when is_integer(owner_guid) do
    case Entity.pid(owner_guid) do
      pid when is_pid(pid) -> send(pid, {:farsight_removed, guid})
      _ -> nil
    end
  end

  defp notify_farsight_owner(_entity, _owner_guid), do: nil

  defp schedule_expiry(state, now) do
    timer = Process.send_after(self(), {:expire, state.expires_at}, max(state.expires_at - now, 0))
    Map.put(state, :expiry_timer, timer)
  end

  defp apply_tick(%{entity: entity, tick: tick} = state) do
    %{caster: caster, spell: spell, effect: effect} = tick
    {x, y, z, _o} = entity.movement_block.position
    radius = entity.dynamic_object.radius

    tick_spell = %{
      spell
      | cast_time_ms: 0,
        hidden_aura?: not UnitSync.visible?(spell),
        effects: [%{effect | type: :apply_aura, semantic: nil}]
    }

    area = %PersistentArea{
      guid: entity.object.guid,
      position: {entity.internal.world, x, y, z},
      radius: radius,
      started_at: state.started_at,
      expires_at: state.expires_at
    }

    context = %{CastContext.from_caster(caster, tick_spell, nil) | persistent_area: area}
    targets = SpellTargetResolver.resolve_query(caster, tick_spell, {:targeted_aoe, {x, y, z}, radius})

    Enum.each(targets, fn target_guid ->
      Entity.receive_spell(target_guid, %{context | target_guid: target_guid}, tick_spell)
    end)

    targets
  end

  def tick_config(caster, %Spell{} = spell, %Effect{} = effect) do
    %{
      caster: caster,
      spell: spell,
      effect: effect,
      interval_ms: 250
    }
  end
end
