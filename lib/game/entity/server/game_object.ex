defmodule ThistleTea.Game.Entity.Server.GameObject do
  @moduledoc """
  Owning GenServer for a game object; serves update-object requests, chest
  loot interactions, and reacts to game-event start/stop for event-gated
  spawns.
  """
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Data.Component.Internal.Summon
  alias ThistleTea.Game.Entity.Data.Component.Internal.Trap
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.GameObject.Chair
  alias ThistleTea.Game.Entity.Server.GameObject.Chest
  alias ThistleTea.Game.Entity.Server.GameObject.Fishing
  alias ThistleTea.Game.Entity.Server.GameObject.Ritual, as: RitualServer
  alias ThistleTea.Game.Entity.Server.GameObject.Trap, as: TrapServer
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgFishNotHooked
  alias ThistleTea.Game.Network.Message.SmsgGameobjectCustomAnim
  alias ThistleTea.Game.Network.Message.SmsgPlayObjectSound
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  def start_link(%GameObject{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%GameObject{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    World.update_position(state)
    state = Visibility.join_entity(state)
    schedule_despawn(state)
    schedule_fishing_bite(state)
    schedule_trap(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    Core.update_object(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:gameobject_use, user_guid, _user_level},
        %GameObject{
          internal: %Internal{ritual: %Ritual{} = ritual, world: world} = internal,
          movement_block: %{position: position}
        } = state
      ) do
    {ritual, result} = RitualServer.use(ritual, user_guid, same_group?(ritual.owner_guid, user_guid))
    state = %{state | internal: %{internal | ritual: ritual}}

    if result in [:waiting, :complete] do
      start_ritual_channel(state, ritual, user_guid)
    end

    if result == :complete do
      cast_ritual_completion(state, ritual, world, position)
      cast_ritual_participant_spell(state, ritual)
      Entity.finish_game_object_channel(ritual.owner_guid, state.object.guid)
      if not ritual.persistent?, do: send(self(), :despawn)
    end

    {:noreply, state}
  end

  def handle_cast(
        {:ritual_user_left, user_guid},
        %GameObject{internal: %Internal{ritual: %Ritual{} = ritual} = internal} = state
      ) do
    {:noreply, %{state | internal: %{internal | ritual: RitualServer.leave(ritual, user_guid)}}}
  end

  def handle_cast(
        {:gameobject_use, user_guid, user_level},
        %GameObject{internal: %Internal{summon: %Summon{} = summon}} = state
      ) do
    with {spell_id, %Spell{} = spell} when is_integer(spell_id) <-
           {summon.spell_id, SpellLoader.load(summon.spell_id || 0)},
         true <- allowed_user?(summon, user_guid) do
      context = %CastContext{
        caster_guid: summon.owner_guid || user_guid,
        caster_level: user_level,
        target_guid: user_guid,
        spell: spell
      }

      Entity.receive_spell(user_guid, context, spell)
      {:noreply, spend_charge(state)}
    else
      _ ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(
        {:loot_view, viewer},
        _from,
        %GameObject{internal: %Internal{fishing: %{owner_guid: owner_guid}}} = state
      )
      when is_integer(owner_guid) and viewer != owner_guid do
    {:reply, {:error, :not_owner}, state}
  end

  def handle_call({:loot_view, viewer}, _from, %GameObject{} = state) do
    {result, state} = Chest.view(state, viewer)
    {:reply, result, state}
  end

  def handle_call({:chair_seat, user_map, {user_x, user_y, user_z} = user_position}, _from, %GameObject{} = state) do
    result =
      with {:ok, {seat_x, seat_y, seat_z, _orientation} = position, stand_state} <-
             Chair.seat(state, user_map, user_position),
           true <- Pathfinding.line_of_sight?(user_map, {user_x, user_y, user_z}, {seat_x, seat_y, seat_z}) do
        {:ok, position, stand_state}
      else
        false -> {:error, :line_of_sight}
        error -> error
      end

    {:reply, result, state}
  end

  def handle_call({:fishing_use, owner_guid, skill}, _from, %GameObject{} = state) do
    {result, state} = Fishing.use(state, owner_guid, skill)
    if match?({:error, reason} when reason in [:not_hooked, :escaped], result), do: send(self(), :despawn)
    {:reply, result, state}
  end

  def handle_call(:fishing_hole_loot, _from, %GameObject{} = state) do
    {result, state} = Fishing.hole_loot(state)

    case result do
      {:ok, _loot, 0} -> send(self(), :fishing_hole_depleted)
      _ -> :ok
    end

    {:reply, result, state}
  end

  def handle_call({:loot_take_item, slot}, _from, %GameObject{} = state) do
    {result, state} = Chest.take_item(state, slot)
    {:reply, result, state}
  end

  def handle_call({:loot_return_item, slot}, _from, %GameObject{} = state) do
    {:reply, :ok, Chest.return_item(state, slot)}
  end

  def handle_call(:loot_take_gold, _from, %GameObject{} = state) do
    {result, state} = Chest.take_gold(state)
    {:reply, result, state}
  end

  def handle_call(
        {:loot_release, viewer},
        _from,
        %GameObject{internal: %Internal{fishing: %{owner_guid: owner_guid}}} = state
      )
      when is_integer(owner_guid) and viewer == owner_guid do
    state = Chest.release(state, viewer)
    send(self(), :despawn)
    {:reply, :ok, state}
  end

  def handle_call({:loot_release, viewer}, _from, %GameObject{} = state) do
    {:reply, :ok, Chest.release(state, viewer)}
  end

  @impl GenServer
  def handle_info({:event_stop, _event}, state) do
    case SpawnPool.deactivate(state) do
      :pooled -> {:noreply, state}
      :unpooled -> despawn(state)
    end
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  def handle_info(:despawn, state) do
    despawn(state)
  end

  def handle_info(:trap_tick, %GameObject{internal: %Internal{trap: %Trap{} = trap}} = state) do
    case TrapServer.target(state) do
      target_guid when is_integer(target_guid) ->
        trigger_trap(state, trap, target_guid)
        despawn(state)

      _ ->
        Process.send_after(self(), :trap_tick, 200)
        {:noreply, state}
    end
  end

  def handle_info(:fishing_bite, %GameObject{} = state) do
    state = Fishing.bite(state)
    Core.update_object(state, :values) |> World.broadcast_packet(state)

    %SmsgGameobjectCustomAnim{guid: state.object.guid}
    |> World.broadcast_packet(state)

    %SmsgPlayObjectSound{sound_id: 3355, guid: state.object.guid}
    |> World.broadcast_packet(state)

    {:noreply, state}
  end

  def handle_info(:fishing_expire, %GameObject{internal: %Internal{fishing: %{consumed?: true}}} = state) do
    {:noreply, state}
  end

  def handle_info(:fishing_expire, %GameObject{internal: %Internal{fishing: fishing}} = state) do
    Network.send_packet(%SmsgFishNotHooked{}, fishing.owner_guid)
    despawn(state)
  end

  def handle_info(:fishing_hole_depleted, %GameObject{} = state) do
    case SpawnPool.recycle(state) do
      :pooled -> {:noreply, state}
      :unpooled -> {:noreply, Fishing.deplete(state)}
    end
  end

  def handle_info(:fishing_hole_respawn, %GameObject{} = state) do
    {:noreply, Fishing.respawn(state)}
  end

  def handle_info(:chest_respawn, %GameObject{} = state) do
    case SpawnPool.recycle(state) do
      :pooled -> {:noreply, state}
      :unpooled -> {:noreply, Chest.respawn(state)}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    finish_ritual_channels(state)
    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end

  defp despawn(state) do
    pid = self()

    Task.start(fn ->
      World.stop_entity(pid)
    end)

    {:noreply, state}
  end

  defp schedule_despawn(%GameObject{internal: %Internal{fishing: %{bite_delay_ms: delay}}})
       when is_integer(delay) and delay > 0 do
    nil
  end

  defp schedule_despawn(%GameObject{internal: %Internal{summon: %Summon{despawn_in_ms: despawn_in_ms}}})
       when is_integer(despawn_in_ms) and despawn_in_ms > 0 do
    Process.send_after(self(), :despawn, despawn_in_ms)
  end

  defp schedule_despawn(_state), do: nil

  defp schedule_fishing_bite(%GameObject{internal: %Internal{fishing: %{bite_delay_ms: delay}}})
       when is_integer(delay) and delay > 0 do
    Process.send_after(self(), :fishing_bite, delay)
    Process.send_after(self(), :fishing_expire, delay + 5_000)
  end

  defp schedule_fishing_bite(_state), do: nil

  defp schedule_trap(%GameObject{internal: %Internal{trap: %Trap{start_delay_ms: delay}}}) do
    Process.send_after(self(), :trap_tick, max(delay, 200))
  end

  defp schedule_trap(_state), do: nil

  defp cast_ritual_completion(state, %Ritual{} = ritual, world, {x, y, z, orientation}) do
    with spell_id when is_integer(spell_id) <- ritual.completion_spell_id,
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      context = %CastContext{
        caster_guid: ritual.owner_guid,
        caster_level: state.game_object.level || 1,
        caster_position: {world, x, y, z},
        caster_orientation: orientation,
        caster_zone: ritual.zone_id,
        target_guid: ritual.target_guid,
        selected_target_guid: ritual.target_guid,
        spell: spell
      }

      Entity.receive_spell(ritual.owner_guid, context, spell)
    end
  end

  defp cast_ritual_participant_spell(state, %Ritual{} = ritual) do
    with spell_id when is_integer(spell_id) <- ritual.caster_target_spell_id,
         target_guid when is_integer(target_guid) <- Enum.random(ritual.users),
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      context = %CastContext{
        caster_guid: target_guid,
        caster_level: state.game_object.level || 1,
        target_guid: target_guid,
        selected_target_guid: target_guid,
        spell: spell
      }

      Entity.receive_spell(target_guid, context, spell)
    end
  end

  defp start_ritual_channel(state, %Ritual{} = ritual, user_guid) do
    with spell_id when is_integer(spell_id) <- ritual.animation_spell_id,
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      duration_ms = state.internal.summon.despawn_in_ms || spell.duration_ms || 0
      Entity.start_game_object_channel(user_guid, state.object.guid, spell, duration_ms)
    end
  end

  defp finish_ritual_channels(%GameObject{object: %{guid: guid}, internal: %Internal{ritual: %Ritual{} = ritual}}) do
    Enum.each(ritual.users, &Entity.finish_game_object_channel(&1, guid))
  end

  defp finish_ritual_channels(%GameObject{}), do: nil

  defp trigger_trap(state, %Trap{owner_guid: owner_guid, spell_id: spell_id}, target_guid) do
    case SpellLoader.load(spell_id) do
      %Spell{} = spell ->
        level = state.game_object.level || 1
        caster = trap_caster(state, owner_guid, level)

        spell
        |> immediate_trap_spell()
        |> deliver_trap_spell(caster, target_guid, level)

        spawn_trap_areas(caster, spell)

      _ ->
        nil
    end
  end

  defp trap_caster(state, owner_guid, level) do
    %{
      object: %{guid: owner_guid},
      unit: %{level: level},
      internal: %{world: state.internal.world},
      movement_block: state.movement_block
    }
  end

  defp immediate_trap_spell(%Spell{} = spell) do
    %{spell | effects: Enum.reject(spell.effects, &(&1.type == :persistent_area_aura))}
  end

  defp deliver_trap_spell(%Spell{effects: []}, _caster, _target_guid, _level), do: nil

  defp deliver_trap_spell(%Spell{} = spell, caster, target_guid, level) do
    caster
    |> SpellTargetResolver.resolve(spell, Targets.unit(target_guid))
    |> Enum.each(fn guid ->
      context = %CastContext{caster_guid: caster.object.guid, caster_level: level, target_guid: guid, spell: spell}
      Entity.receive_spell(guid, context, spell)
    end)
  end

  defp spawn_trap_areas(caster, %Spell{} = spell) do
    {x, y, z, _o} = caster.movement_block.position

    Enum.each(spell.effects, fn
      %{type: :persistent_area_aura} = effect ->
        event = Event.spawn_area_effect(spell, effect, {x, y, z}, spell.duration_ms || 0)
        EventSink.emit(caster, event)

      _effect ->
        nil
    end)
  end

  defp spend_charge(%GameObject{internal: %Internal{summon: %Summon{charges: charges} = summon} = internal} = state)
       when is_integer(charges) do
    if charges > 1 do
      %{state | internal: %{internal | summon: %{summon | charges: charges - 1}}}
    else
      send(self(), :despawn)
      %{state | internal: %{internal | summon: %{summon | charges: 0, spell_id: nil}}}
    end
  end

  defp spend_charge(state), do: state

  defp allowed_user?(%Summon{party_only?: true, owner_guid: owner_guid}, user_guid) when is_integer(owner_guid) do
    user_guid == owner_guid or same_group?(owner_guid, user_guid)
  end

  defp allowed_user?(_summon, _user_guid), do: true

  defp same_group?(owner_guid, user_guid) do
    case {PartySystem.group_of(owner_guid), PartySystem.group_of(user_guid)} do
      {%Party.Group{id: id}, %Party.Group{id: id}} -> true
      _ -> false
    end
  end
end
