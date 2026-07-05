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
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Visibility

  @default_respawn_ms 300_000

  def lootable?(%GameObject{internal: %Internal{loot: %InternalLoot{}}}), do: true
  def lootable?(%GameObject{}), do: false

  def view(%GameObject{} = state, viewer) do
    case ensure_session(state) do
      {%LootSession{} = session, state} ->
        session = LootSession.add_viewer(session, viewer)
        {{:ok, LootSession.view(session, viewer)}, put_session(state, session)}

      :no_loot ->
        {{:error, :no_loot}, state}
    end
  end

  def take_item(%GameObject{} = state, slot) do
    with %LootSession{} = session <- session(state),
         {:ok, item, session} <- LootSession.take_item(session, slot) do
      {{:ok, item}, put_session(state, session)}
    else
      {:error, reason} -> {{:error, reason}, state}
      _no_session -> {{:error, :no_loot}, state}
    end
  end

  def return_item(%GameObject{} = state, slot) do
    case session(state) do
      %LootSession{} = session -> put_session(state, LootSession.return_item(session, slot))
      _no_session -> state
    end
  end

  def take_gold(%GameObject{} = state) do
    with %LootSession{} = session <- session(state),
         {:ok, gold, session} <- LootSession.take_gold(session) do
      {{:ok, gold}, put_session(state, session)}
    else
      {:error, reason} -> {{:error, reason}, state}
      _no_session -> {{:error, :no_loot}, state}
    end
  end

  def release(%GameObject{} = state, viewer) do
    case session(state) do
      %LootSession{} = session ->
        session = LootSession.remove_viewer(session, viewer)
        state = put_session(state, session)
        if LootSession.finished?(session), do: despawn(state), else: state

      _no_session ->
        state
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
