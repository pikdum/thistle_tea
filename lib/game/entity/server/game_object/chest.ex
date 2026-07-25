defmodule ThistleTea.Game.Entity.Server.GameObject.Chest do
  @moduledoc """
  Chest phase for lootable game objects: generates the loot session lazily
  on first open, serves the loot interactions, and once emptied despawns
  the object for its spawn-row respawn delay before bringing it back with
  fresh loot.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Visibility

  @default_respawn_ms 300_000

  def lootable?(%GameObject{internal: %Internal{loot: %InternalLoot{}}}), do: true
  def lootable?(%GameObject{}), do: false

  def view(%GameObject{} = state, %Actor{} = actor) do
    case ensure_session(state) do
      {%LootSession{} = session, state} ->
        case LootSession.view(session, actor) do
          {:ok, %Loot{} = loot} ->
            session = LootSession.add_viewer(session, actor)
            {{:ok, loot}, put_session(state, session)}

          {:error, reason} ->
            {{:error, reason}, state}
        end

      :no_loot ->
        {{:error, :no_loot}, state}
    end
  end

  def reserve_item(%GameObject{} = state, %Actor{} = actor, slot, owner_pid) when is_pid(owner_pid) do
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
    with %LootSession{} = session <- session(state),
         {:ok, gold, session} <- LootSession.take_gold(session, actor) do
      {{:ok, gold}, put_session(state, session)}
    else
      {:error, reason} -> {{:error, reason}, state}
      _no_session -> {{:error, :no_loot}, state}
    end
  end

  def release(%GameObject{} = state, %Actor{} = actor) do
    case session(state) do
      %LootSession{} = session ->
        session = LootSession.remove_viewer(session, actor)
        state = put_session(state, session)
        if LootSession.finished?(session), do: despawn(state), else: state

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

    case session(state) do
      %LootSession{} = session -> put_session(state, LootSession.release(session, token))
      _no_session -> state
    end
  end

  def respawn(%GameObject{internal: %Internal{loot: %InternalLoot{} = loot}} = state) do
    state = put_internal_loot(state, %{loot | session: nil, corpse_removed?: false})
    World.update_position(state)
    Visibility.join_entity(state)
  end

  def respawn(%GameObject{} = state), do: state

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
