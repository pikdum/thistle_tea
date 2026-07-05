defmodule ThistleTea.Game.Entity.Server.GameObject do
  @moduledoc """
  Owning GenServer for a game object; serves update-object requests, chest
  loot interactions, and reacts to game-event start/stop for event-gated
  spawns.
  """
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Summon
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.GameObject.Chest
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
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
  def handle_call({:loot_view, viewer}, _from, %GameObject{} = state) do
    {result, state} = Chest.view(state, viewer)
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

  def handle_call({:loot_release, viewer}, _from, %GameObject{} = state) do
    {:reply, :ok, Chest.release(state, viewer)}
  end

  @impl GenServer
  def handle_info({:event_stop, _event}, state) do
    despawn(state)
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  def handle_info(:despawn, state) do
    despawn(state)
  end

  def handle_info(:chest_respawn, %GameObject{} = state) do
    {:noreply, Chest.respawn(state)}
  end

  @impl GenServer
  def terminate(_reason, state) do
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

  defp schedule_despawn(%GameObject{internal: %Internal{summon: %Summon{despawn_in_ms: despawn_in_ms}}})
       when is_integer(despawn_in_ms) and despawn_in_ms > 0 do
    Process.send_after(self(), :despawn, despawn_in_ms)
  end

  defp schedule_despawn(_state), do: nil

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
