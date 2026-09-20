defmodule ThistleTea.Game.Entity.Logic.Auction.Query do
  @moduledoc """
  Filters and paginates listings within one linked auction market. Boundary
  callbacks provide item eligibility and localized names, including suffixes.
  """

  alias ThistleTea.Game.Entity.Data.Auction.Book
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Auction.Query
  alias ThistleTea.Game.Entity.Data.Item

  @any 0xFFFFFFFF
  @page_size 50

  def search(%Book{} = book, %House{} = house, %Query{} = query, now, opts \\ []) do
    usable = Keyword.get(opts, :usable, fn _item -> false end)
    item_name = Keyword.get(opts, :item_name, &Item.template(&1).name)
    name = String.downcase(query.name)

    book
    |> active(house, now)
    |> Enum.filter(&matches?(&1.item, query, name, usable, item_name))
    |> Enum.sort_by(&{&1.buyout, &1.id})
    |> page(query.offset)
  end

  def owned(%Book{} = book, %House{} = house, owner, offset, now) do
    book |> active(house, now) |> Enum.filter(&(&1.owner == owner)) |> Enum.sort_by(& &1.id) |> page(offset)
  end

  def bids(%Book{} = book, %House{} = house, bidder, refresh_ids, offset, now) when is_list(refresh_ids) do
    auctions = active(book, house, now)
    by_id = Map.new(auctions, &{&1.id, &1})
    refreshed = refresh_ids |> Enum.uniq() |> Enum.flat_map(&List.wrap(Map.get(by_id, &1)))
    current = auctions |> Enum.filter(&(&1.bidder == bidder)) |> Enum.sort_by(& &1.id)
    (refreshed ++ current) |> Enum.uniq_by(& &1.id) |> page(offset)
  end

  defp active(%Book{auctions: auctions}, %House{market: market}, now) do
    auctions |> Map.values() |> Enum.filter(&(&1.house.market == market and &1.expires_at > now))
  end

  defp matches?(%Item{} = item, %Query{} = query, name, usable, item_name) do
    template = Item.template(item)

    category?(query.class, template.class) and category?(query.subclass, template.subclass) and
      slot?(query.inventory_type, template.inventory_type) and quality?(query.quality, template.quality) and
      level?(query, template.required_level) and (not query.usable? or usable.(item)) and
      (name == "" or String.contains?(String.downcase(item_name.(item)), name))
  end

  defp category?(@any, _actual), do: true
  defp category?(expected, actual), do: expected == actual
  defp slot?(5, 20), do: true
  defp slot?(expected, actual), do: category?(expected, actual)
  defp quality?(@any, _actual), do: true
  defp quality?(minimum, actual), do: actual >= minimum

  defp level?(%Query{level_min: minimum, level_max: maximum}, level) do
    (minimum == 0 or level >= minimum) and (maximum == 0 or level <= maximum)
  end

  defp page(auctions, offset), do: {Enum.slice(auctions, max(offset, 0), @page_size), length(auctions)}
end
