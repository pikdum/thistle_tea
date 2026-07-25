defmodule ThistleTea.Game.Player.Looting do
  @moduledoc """
  Player-owned loot orchestration: builds actor snapshots, opens and closes
  sessions, transfers reserved items, and projects the resulting packets.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Loot.ActorFactory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @loot_method_master_loot 2

  def actor(%{character: %Character{} = character}, loot_guid) do
    ActorFactory.for_character(character, loot_guid)
  end

  def remote_actor(guid, loot_guid), do: ActorFactory.for_guid(guid, loot_guid)

  def open(state, guid, opts \\ [])

  def open(%{character: %Character{} = character} = state, guid, opts) do
    actor = actor(state, guid)

    with false <- Core.dead?(character),
         {:ok, %Loot{} = loot} <- Entity.call(guid, {:loot_view, actor}) do
      Network.send_packet(%Message.SmsgLootResponse{
        guid: guid,
        loot: loot,
        loot_type: Keyword.get(opts, :loot_type, 1)
      })

      maybe_send_master_list(state, guid)
      %{state | loot_guid: guid}
    else
      {:error, :nothing_to_take} ->
        Entity.call(guid, {:loot_release, actor})
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state

      {:error, :no_permission} ->
        Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: %Loot{}})
        state

      _ ->
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state
    end
  end

  def open(state, guid, _opts) do
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
    state
  end

  def release(%{character: %Character{}} = state) when is_integer(state.loot_guid) do
    actor = actor(state, state.loot_guid)
    Entity.call(state.loot_guid, {:loot_release, actor})
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: state.loot_guid})
    %{state | loot_guid: nil}
  end

  def release(state), do: state

  defp maybe_send_master_list(%{guid: viewer}, corpse_guid) do
    with %Party.Group{loot_method: @loot_method_master_loot, master_looter: ^viewer} = group <-
           PartySystem.group_of(viewer),
         {^corpse_guid, map, x, y, z} <- SpatialHash.get_entity(corpse_guid) do
      member_guids = MapSet.new(group.members, & &1.guid)

      looters =
        SpatialHash.query(:players, map, x, y, z, Experience.group_reward_distance())
        |> Enum.map(fn {guid, _distance} -> guid end)
        |> Enum.filter(&MapSet.member?(member_guids, &1))

      packet = %Message.SmsgLootMasterList{looters: looters}
      Enum.each(looters, &Network.send_packet(packet, &1))
    else
      _ -> :ok
    end
  end
end
