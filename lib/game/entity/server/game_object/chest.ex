defmodule ThistleTea.Game.Entity.Server.GameObject.Chest do
  @moduledoc """
  Chest phase for lootable game objects: generates the loot session lazily
  on first open, serves the loot interactions, and once emptied despawns
  the object for its spawn-row respawn delay before bringing it back with
  fresh loot.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Gathering, as: GatheringState
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Gathering
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Logic.OpenLock
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Visibility

  @default_respawn_ms 300_000

  def lootable?(%GameObject{internal: %Internal{loot: %InternalLoot{}}}), do: true
  def lootable?(%GameObject{}), do: false

  def view(%GameObject{} = state, %Actor{} = actor) do
    if authorized?(state, actor), do: view_authorized(state, actor), else: {{:error, :locked}, state}
  end

  defp authorized?(%GameObject{internal: %{gathering: %GatheringState{lock_id: id, opened_by: opened}}}, actor)
       when id > 0 do
    Map.has_key?(opened, actor.guid)
  end

  defp authorized?(_state, _actor), do: true

  defp view_authorized(%GameObject{} = state, %Actor{} = actor) do
    case ensure_session(state) do
      {%LootSession{} = session, state} ->
        case LootSession.view(session, actor) do
          {:ok, %Loot{} = loot} ->
            session = LootSession.add_viewer(session, actor)
            {{:ok, loot}, put_session(state, session)}

          {:error, :nothing_to_take} ->
            {{:error, :nothing_to_take}, put_session(state, LootSession.add_viewer(session, actor))}

          {:error, reason} ->
            {{:error, reason}, state}
        end

      :no_loot ->
        {{:error, :no_loot}, state}
    end
  end

  def reserve_item(%GameObject{} = state, %Actor{} = actor, slot, owner_pid) when is_pid(owner_pid) do
    if authorized?(state, actor),
      do: reserve_authorized(state, actor, slot, owner_pid),
      else: {{:error, :locked}, state}
  end

  defp reserve_authorized(state, actor, slot, owner_pid) do
    case session(state) do
      %LootSession{} = session ->
        token = Process.monitor(owner_pid)

        case LootSession.reserve_item(session, actor, slot, token) do
          {:ok, %Reservation{} = reservation, session} ->
            {{:ok, reservation}, put_session(state, session)}

          {:error, reason} ->
            Process.demonitor(token, [:flush])
            {{:error, reason}, state}
        end

      _no_session ->
        {{:error, :no_loot}, state}
    end
  end

  def take_gold(%GameObject{} = state, %Actor{} = actor) do
    with true <- authorized?(state, actor),
         %LootSession{} = session <- session(state),
         {:ok, gold, session} <- LootSession.take_gold(session, actor) do
      {{:ok, gold}, put_session(state, session)}
    else
      {:error, reason} -> {{:error, reason}, state}
      _no_session -> {{:error, :no_loot}, state}
    end
  end

  def release(%GameObject{} = state, %Actor{} = actor) do
    if authorized?(state, actor), do: release_authorized(state, actor), else: state
  end

  defp release_authorized(state, actor) do
    case session(state) do
      %LootSession{} = session ->
        session = LootSession.remove_viewer(session, actor)
        state = put_session(state, session)
        state = if LootSession.finished?(session), do: finish_harvest(state, actor), else: state
        close_access(state, actor)

      _no_session ->
        state
    end
  end

  def commit(%GameObject{} = state, %Commit{} = command) do
    with %LootSession{} = session <- session(state),
         {:ok, %Loot.Item{slot: slot}, session} <- LootSession.commit(session, command) do
      Process.demonitor(command.token, [:flush])
      packet = %Message.SmsgLootRemoved{slot: slot}
      session |> LootSession.viewers() |> Enum.each(&Network.send_packet(packet, &1))
      {:ok, put_session(state, session)}
    else
      _ -> {{:error, :invalid_reservation}, state}
    end
  end

  def release_reservation(%GameObject{} = state, %Release{} = command) do
    with %LootSession{} = session <- session(state),
         {:ok, session} <- LootSession.release(session, command) do
      Process.demonitor(command.token, [:flush])
      {:ok, put_session(state, session)}
    else
      _ -> {{:error, :invalid_reservation}, state}
    end
  end

  def reservation_lost(%GameObject{} = state, token) when is_reference(token) do
    Process.demonitor(token, [:flush])
    state = release_lost_reservation(state, token)

    case state.internal.gathering do
      %GatheringState{viewer_monitors: monitors} ->
        case Map.get(monitors, token) do
          %Actor{} = actor -> release(state, actor)
          nil -> state
        end

      _ ->
        state
    end
  end

  defp release_lost_reservation(state, token) do
    case session(state) do
      %LootSession{} = session -> put_session(state, LootSession.release(session, token))
      _no_session -> state
    end
  end

  def respawn(%GameObject{internal: %Internal{loot: %InternalLoot{} = loot}} = state) do
    clear_viewer_monitors(state.internal.gathering)
    state = put_internal_loot(state, %{loot | session: nil, corpse_removed?: false})
    state = put_gathering(state, GatheringState.reset(state.internal.gathering))
    World.update_position(state)
    Visibility.join_entity(state)
  end

  def respawn(%GameObject{} = state), do: state

  defp finish_harvest(%GameObject{internal: %{gathering: %GatheringState{} = gathering}} = state, actor) do
    uses = gathering.uses + 1
    opened = Map.get(gathering.opened_by, actor.guid, %OpenLock{required: 175})
    state = put_gathering(state, %{gathering | uses: uses, opened_by: %{}})

    if Gathering.replenish?(
         uses,
         gathering.min_uses,
         gathering.max_uses,
         opened.value,
         opened.required,
         :rand.uniform() * 100
       ) do
      put_session(state, nil)
    else
      despawn(state)
    end
  end

  defp finish_harvest(state, _actor), do: despawn(state)

  defp close_access(%GameObject{internal: %{gathering: %GatheringState{} = gathering}} = state, actor) do
    {closed, monitors} = Enum.split_with(gathering.viewer_monitors, fn {_ref, viewer} -> viewer.guid == actor.guid end)
    Enum.each(closed, fn {ref, _viewer} -> Process.demonitor(ref, [:flush]) end)

    put_gathering(state, %{
      gathering
      | opened_by: Map.delete(gathering.opened_by, actor.guid),
        viewer_monitors: Map.new(monitors)
    })
  end

  defp close_access(state, _actor), do: state

  defp clear_viewer_monitors(%GatheringState{viewer_monitors: monitors}) do
    Enum.each(monitors, fn {ref, _actor} -> Process.demonitor(ref, [:flush]) end)
  end

  defp clear_viewer_monitors(nil), do: :ok

  defp put_gathering(state, gathering), do: %{state | internal: %{state.internal | gathering: gathering}}

  defp despawn(%GameObject{internal: %Internal{loot: %InternalLoot{} = loot}} = state) do
    state = Visibility.leave_entity(state)
    World.remove_position(state)
    Process.send_after(self(), :chest_respawn, respawn_ms(state))
    put_internal_loot(state, %{loot | session: nil, corpse_removed?: true})
  end

  defp respawn_ms(%GameObject{internal: %Internal{spawn: %Spawn{respawn_delay_ms: ms}}})
       when is_integer(ms) and ms > 0 do
    ms
  end

  defp respawn_ms(%GameObject{}), do: @default_respawn_ms

  defp ensure_session(%GameObject{internal: %Internal{loot: %InternalLoot{corpse_removed?: true}}}), do: :no_loot

  defp ensure_session(%GameObject{internal: %Internal{loot: %InternalLoot{session: %LootSession{} = session}}} = state) do
    {session, state}
  end

  defp ensure_session(%GameObject{internal: %Internal{loot: %InternalLoot{} = loot}} = state) do
    session = LootSession.new(LootLoader.generate_gameobject(loot.id, loot.min_gold, loot.max_gold), nil)
    {session, put_session(state, session)}
  end

  defp ensure_session(%GameObject{}), do: :no_loot

  defp session(%GameObject{internal: %Internal{loot: %InternalLoot{session: session}}}), do: session
  defp session(%GameObject{}), do: nil

  defp put_session(%GameObject{internal: %Internal{loot: %InternalLoot{} = loot}} = state, session) do
    put_internal_loot(state, %{loot | session: session})
  end

  defp put_internal_loot(%GameObject{internal: internal} = state, loot) do
    %{state | internal: %{internal | loot: loot}}
  end
end
