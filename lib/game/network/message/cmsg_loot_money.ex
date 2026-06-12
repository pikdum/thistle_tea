defmodule ThistleTea.Game.Network.Message.CmsgLootMoney do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_MONEY

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{} = c, loot_guid: loot_guid} = state)
      when is_integer(loot_guid) do
    case Entity.call(loot_guid, :loot_take_gold) do
      {:ok, gold} ->
        share = split_gold(state.guid, c, gold)
        player = %{c.player | coinage: c.player.coinage + share}
        Network.send_packet(%Message.SmsgLootMoneyNotify{money: share})
        Network.send_packet(%Message.SmsgLootClearMoney{})
        InventoryUpdate.apply(state, {:ok, player})

      _ ->
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  defp split_gold(guid, character, gold) do
    case PartySystem.group_of(guid) do
      %Party.Group{} = group ->
        others = nearby_members(guid, character, group)
        share = div(gold, length(others) + 1)
        Enum.each(others, &Entity.receive_money(&1, share))
        share

      _ ->
        gold
    end
  end

  defp nearby_members(guid, character, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    character
    |> World.nearby_players(Experience.group_reward_distance())
    |> Enum.map(fn {other_guid, _distance} -> other_guid end)
    |> Enum.filter(fn other_guid -> other_guid != guid and MapSet.member?(member_guids, other_guid) end)
  end
end
