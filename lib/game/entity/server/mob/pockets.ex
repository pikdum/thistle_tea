defmodule ThistleTea.Game.Entity.Server.Mob.Pockets do
  @moduledoc """
  Owns living-creature loot sessions independently of corpse loot. Reservations
  survive death until committed or released, while new interactions stop.
  """
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Logic.Pickpocket
  alias ThistleTea.Game.Entity.Server.Mob.Respawn
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  def open(%Mob{} = mob, %Actor{} = actor, level) do
    if Pickpocket.available?(mob) and Actor.within?(actor, 5.0) do
      session = Map.get(sessions(mob), actor.guid) || generate(mob, actor, level)
      mob = put_session(mob, actor.guid, session)

      case LootSession.view(session, actor) do
        {:ok, loot} -> {{:ok, loot}, put_session(mob, actor.guid, LootSession.add_viewer(session, actor))}
        error -> {error, mob}
      end
    else
      {{:error, :no_loot}, mob}
    end
  end

  def interact(%Mob{} = mob, %Actor{} = actor, command, owner_pid) do
    with true <- Pickpocket.available?(mob),
         %LootSession{} = session <- Map.get(sessions(mob), actor.guid),
         true <- actor.guid in LootSession.viewers(session) do
      execute(mob, session, actor, command, owner_pid)
    else
      _ -> {{:error, :no_loot}, mob}
    end
  end

  def validate_commit(%Mob{} = mob, actor, token) do
    LootSession.validate_commit(Map.get(sessions(mob), actor.guid), actor, token)
  end

  def owns_reservation?(%Mob{} = mob, token) do
    Enum.any?(sessions(mob), fn {_guid, session} -> Map.has_key?(session.reservations, token) end)
  end

  def commit(%Mob{} = mob, %Commit{actor_guid: guid} = command) do
    with %LootSession{} = session <- Map.get(sessions(mob), guid),
         {:ok, item, session} <- LootSession.commit(session, command) do
      Process.demonitor(command.token, [:flush])
      Enum.each(LootSession.viewers(session), &Network.send_packet(%Message.SmsgLootRemoved{slot: item.slot}, &1))
      mob = put_session(mob, guid, session)
      Respawn.maybe_continue(mob)
      {:ok, mob}
    else
      _ -> {{:error, :invalid_reservation}, mob}
    end
  end

  def release_reservation(%Mob{} = mob, %Release{actor_guid: guid} = command) do
    with %LootSession{} = session <- Map.get(sessions(mob), guid),
         {:ok, session} <- LootSession.release(session, command) do
      Process.demonitor(command.token, [:flush])
      mob = put_session(mob, guid, session)
      Respawn.maybe_continue(mob)
      {:ok, mob}
    else
      _ -> {{:error, :invalid_reservation}, mob}
    end
  end

  def reservation_lost(%Mob{} = mob, token) do
    Process.demonitor(token, [:flush])

    mob =
      Enum.reduce(sessions(mob), mob, fn {guid, session}, mob ->
        put_session(mob, guid, LootSession.release(session, token))
      end)

    Respawn.maybe_continue(mob)
    mob
  end

  def release(%Mob{} = mob, %Actor{} = actor) do
    case Map.get(sessions(mob), actor.guid) do
      %LootSession{} = session -> put_session(mob, actor.guid, LootSession.remove_viewer(session, actor))
      _ -> mob
    end
  end

  def close(%Mob{} = mob) do
    Enum.reduce(sessions(mob), mob, fn {guid, session}, mob ->
      packet = %Message.SmsgLootReleaseResponse{guid: mob.object.guid}
      Enum.each(LootSession.viewers(session), &Network.send_packet(packet, &1))
      put_session(mob, guid, %{session | viewers: MapSet.new()})
    end)
  end

  def pending?(%Mob{} = mob), do: Enum.any?(sessions(mob), fn {_guid, session} -> LootSession.pending?(session) end)

  defp execute(mob, session, actor, {:reserve_item, slot}, owner_pid) do
    token = Process.monitor(owner_pid)

    case LootSession.reserve_item(session, actor, slot, token) do
      {:ok, %Reservation{} = reservation, session} ->
        {{:ok, reservation}, put_session(mob, actor.guid, session)}

      error ->
        Process.demonitor(token, [:flush])
        {error, mob}
    end
  end

  defp execute(mob, session, actor, :take_gold, _owner_pid) do
    case LootSession.take_gold(session, actor) do
      {:ok, gold, session} -> {{:ok, gold}, put_session(mob, actor.guid, session)}
      error -> {error, mob}
    end
  end

  defp generate(mob, actor, level) do
    mob.internal.loot.pickpocket_id
    |> LootLoader.generate_pickpocket(mob.unit.level, level)
    |> Pickpocket.session(actor, map_size(sessions(mob)) > 0)
  end

  defp sessions(%Mob{internal: %{loot: %{pockets: pockets}}}) when is_map(pockets), do: pockets
  defp sessions(%Mob{}), do: %{}

  defp put_session(%Mob{internal: internal} = mob, guid, session) do
    loot = %{internal.loot | pockets: Map.put(sessions(mob), guid, session)}
    %{mob | internal: %{internal | loot: loot}}
  end
end
