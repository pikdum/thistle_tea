defmodule ThistleTea.Game.Entity.Server.DynamicObject do
  @moduledoc """
  Owning GenServer for an area-effect dynamic object: runs its periodic damage
  ticks and despawns itself when the effect expires (`restart: :temporary` so
  the supervisor doesn't resurrect it).
  """
  use GenServer, restart: :temporary

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.DynamicObject
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.PersistentArea
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AreaEffects
  alias ThistleTea.Game.World.Visibility

  require Logger

  def start_link(%{entity: %DynamicObject{} = entity} = opts) do
    GenServer.start_link(__MODULE__, opts, name: EntityRegistry.via(entity.object.guid))
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

  def handle_info(:expire, state) do
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
