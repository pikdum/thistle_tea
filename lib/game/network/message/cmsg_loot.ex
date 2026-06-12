defmodule ThistleTea.Game.Network.Message.CmsgLoot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @loot_method_master_loot 2

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    with false <- Core.dead?(c),
         {:ok, %Loot{} = loot} <- Entity.call(guid, {:loot_view, state.guid}) do
      Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: Quests.filter_loot(loot, c)})
      maybe_send_master_list(state, guid)
      Map.put(state, :loot_guid, guid)
    else
      {:error, :no_permission} ->
        Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: %Loot{}})
        state

      _ ->
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

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
