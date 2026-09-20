defmodule ThistleTea.Game.World.Loader.AuctionHouse do
  @moduledoc """
  Startup cache of auction-house fees and faction-linked markets. Runtime
  auctioneer interactions resolve only cached rows and published factions.
  """

  import Bitwise, only: [band: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Auction.House

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _table -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    for row <- DBC.all(AuctionHouse) do
      house = %House{
        id: row.id,
        market: market(row.id),
        deposit_percent: row.deposit_rate,
        cut_percent: row.consignment_rate
      }

      :ets.insert(table, {row.id, house})
    end

    :ok
  end

  def get(id, table \\ __MODULE__) do
    case :ets.lookup(table, id) do
      [{^id, %House{} = house}] -> house
      _ -> nil
    end
  end

  def for_faction(faction, table \\ __MODULE__), do: get(house_id(faction), table)

  defp house_id(%FactionTemplate{id: id}) when id in [11, 12], do: 1
  defp house_id(%FactionTemplate{id: id}) when id in [55, 57, 534], do: 2
  defp house_id(%FactionTemplate{id: id}) when id in [79, 80], do: 3
  defp house_id(%FactionTemplate{id: id}) when id in [68, 71], do: 4
  defp house_id(%FactionTemplate{id: id}) when id in [104, 105], do: 5
  defp house_id(%FactionTemplate{id: id}) when id in [29, 85], do: 6
  defp house_id(%FactionTemplate{id: id}) when id in [120, 474, 855], do: 7
  defp house_id(%FactionTemplate{faction_group: group}) when band(group, 2) != 0, do: 1
  defp house_id(%FactionTemplate{faction_group: group}) when band(group, 4) != 0, do: 6
  defp house_id(_faction), do: 7

  defp market(id) when id in 1..3, do: :alliance
  defp market(id) when id in 4..6, do: :horde
  defp market(_id), do: :neutral
end
