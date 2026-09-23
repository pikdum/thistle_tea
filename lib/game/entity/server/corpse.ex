defmodule ThistleTea.Game.Entity.Server.Corpse do
  @moduledoc """
  Owns a released body or lootable bones, serializes insignia claims and money
  transfers, and publishes its appearance until removal or decay.
  """
  use GenServer

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Corpse, as: Body
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Insignia
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InsigniaTarget
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  require Logger

  @bones_lifetime_ms 3_600_000

  def child_spec(state), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [state]}, restart: :temporary}

  def start_link(%Corpse{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%Corpse{} = state) do
    Process.flag(:trap_exit, true)

    owner_metadata =
      state.corpse.owner
      |> Metadata.get()
      |> Kernel.||(%{})
      |> Map.take([:faction_template, :faction_template_id, :faction_can_have_reputation?])

    body = state.internal.corpse || %Body{}
    metadata = Map.merge(body.faction_metadata, owner_metadata)
    state = %{state | internal: %{state.internal | corpse: %{body | faction_metadata: metadata}}}

    Metadata.put(
      state.object.guid,
      Map.merge(metadata, %{
        owner: state.corpse.owner,
        ghost_time: state.internal.corpse_reclaim.released_at,
        bones?: bones?(state),
        insignia: %{
          team: body.team,
          level: body.level,
          available?: available?(state),
          death_id: state.internal.corpse_reclaim.expires_at
        }
      })
    )

    World.update_position(state)
    state = Visibility.join_entity(state)
    if bones?(state), do: Process.send_after(self(), :expire, @bones_lifetime_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:remove_insignia, looter_guid, death_id}, _from, state) do
    {x, y, z, _orientation} = state.movement_block.position

    body = %{
      team: state.internal.corpse.team,
      position: {state.internal.world, x, y, z},
      available?: available?(state),
      visible?: true,
      los?: World.line_of_sight?(state, looter_guid)
    }

    with true <- state.internal.corpse_reclaim.expires_at == death_id,
         :ok <- Insignia.validate_actor(InsigniaTarget.actor(looter_guid), body),
         bones = build_bones(state, looter_guid),
         {:ok, _pid} <- World.start_entity(bones) do
      {:stop, :normal, {:ok, bones.object.guid}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _invalid -> {:reply, {:error, :bad_targets}, state}
    end
  rescue
    error ->
      Logger.error("Insignia removal failed: #{Exception.message(error)}")
      {:reply, {:error, :bad_targets}, state}
  end

  def handle_call({command, %Actor{} = actor}, _from, state)
      when command in [:insignia_view, :loot_view, :loot_take_gold, :loot_release] do
    {reply, state} = loot_command(state, actor, command)
    {:reply, reply, state}
  rescue
    error ->
      Logger.error("Corpse loot failed: #{Exception.message(error)}")
      {:reply, {:error, :no_loot}, state}
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, :no_loot}, state}

  @impl GenServer
  def handle_info(:expire, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    Core.update_object(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    case state.internal.corpse.session do
      %LootSession{} = session ->
        Enum.each(
          LootSession.viewers(session),
          &Network.send_packet(%Message.SmsgLootReleaseResponse{guid: state.object.guid}, &1)
        )

      _missing ->
        :ok
    end

    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end

  defp loot_command(
         %Corpse{internal: %{corpse: %{session: %LootSession{} = session} = body}} = state,
         actor,
         :insignia_view
       ) do
    if body.looter_guid == actor.guid do
      view(state, actor, %{session | interaction_distance: Insignia.range()})
    else
      {{:error, :no_permission}, state}
    end
  end

  defp loot_command(%Corpse{internal: %{corpse: %{session: %LootSession{} = session}}} = state, actor, :loot_view) do
    view(state, actor, session)
  end

  defp loot_command(%Corpse{internal: %{corpse: %{session: %LootSession{} = session}}} = state, actor, :loot_take_gold) do
    case LootSession.take_gold(session, actor) do
      {:ok, gold, session} ->
        session
        |> LootSession.viewers()
        |> Enum.reject(&(&1 == actor.guid))
        |> Enum.each(&Network.send_packet(%Message.SmsgLootClearMoney{}, &1))

        {{:ok, gold}, put_session(state, session)}

      error ->
        {error, state}
    end
  end

  defp loot_command(%Corpse{internal: %{corpse: %{session: %LootSession{} = session}}} = state, actor, :loot_release) do
    {:ok, put_session(state, LootSession.remove_viewer(session, actor))}
  end

  defp loot_command(state, _actor, _command), do: {{:error, :no_loot}, state}

  defp view(state, actor, session) do
    case LootSession.view(session, actor) do
      {:ok, loot} -> {{:ok, loot}, put_session(state, LootSession.add_viewer(state.internal.corpse.session, actor))}
      error -> {error, state}
    end
  end

  defp put_session(state, session) do
    flags = if LootSession.finished?(session), do: 0, else: 1

    updated = %{
      state
      | corpse: %{state.corpse | dynamic_flags: flags},
        internal: %{state.internal | corpse: %{state.internal.corpse | session: session}}
    }

    if flags != state.corpse.dynamic_flags,
      do: updated |> Core.update_object(:values) |> World.broadcast_packet(updated)

    updated
  end

  defp build_bones(state, looter_guid) do
    guid = Guid.from_low_guid(:corpse, 0x80000000 + :erlang.unique_integer([:positive, :monotonic]))
    loot = %Loot{gold: Insignia.gold(state.internal.corpse.level, Enum.random(50..150))}
    body = %{state.internal.corpse | session: LootSession.new(loot, nil), looter_guid: looter_guid}

    %{
      state
      | object: %{state.object | guid: guid},
        corpse: %{state.corpse | flags: 0x05, items: 0, dynamic_flags: 1},
        internal: %{state.internal | corpse: body, visibility_cell: nil}
    }
  end

  defp bones?(state), do: ((state.corpse.flags || 0) &&& 1) != 0
  defp available?(state), do: ((state.corpse.flags || 0) &&& 0x20) != 0 and not bones?(state)
end
