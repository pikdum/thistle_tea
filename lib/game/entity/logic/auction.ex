defmodule ThistleTea.Game.Entity.Logic.Auction do
  @moduledoc """
  Pure vanilla auction listing, bidding, cancellation, and settlement rules.
  Money is reserved by bids and returned by mail, while a successful sale
  refunds its deposit and subtracts the house cut from the winning bid.
  """

  alias ThistleTea.Game.Entity.Data.Auction
  alias ThistleTea.Game.Entity.Data.Auction.Actor
  alias ThistleTea.Game.Entity.Data.Auction.Book
  alias ThistleTea.Game.Entity.Data.Auction.Change
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Auction.Notice
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Auction.Settlement

  @maximum_price 2_000_000_000
  @durations [120, 480, 1_440]

  def maximum_price, do: @maximum_price
  def durations, do: @durations

  def deposit(%House{} = house, %Item{} = item, duration_minutes) when duration_minutes in @durations do
    div(
      Item.template(item).sell_price * item.item.stack_count * div(duration_minutes, 120) * house.deposit_percent,
      100
    )
  end

  def cut(%Auction{house: %House{cut_percent: percent}, bid: bid}), do: div(percent * bid, 100)
  def increment(%Auction{bid: bid}), do: max(div(bid, 100) * 5, 1)

  def sell(%Book{} = book, %Actor{} = actor, %House{} = house, %Item{} = item, terms, now)
      when is_map(terms) and is_integer(now) do
    with :ok <- validate_terms(terms),
         :ok <- sale_item(book, actor, item),
         cost = deposit(house, item, terms.duration_minutes),
         :ok <- funds(actor, cost) do
      item = %{item | item: %{item.item | owner: 0, contained: 0}}

      auction = %Auction{
        id: book.next_id,
        house: house,
        item: item,
        owner: actor.guid,
        owner_account: actor.account_id,
        start_bid: terms.start_bid,
        buyout: terms.buyout,
        deposit: cost,
        created_at: now,
        expires_at: now + terms.duration_minutes * 60_000
      }

      book = %{book | next_id: book.next_id + 1, auctions: Map.put(book.auctions, auction.id, auction)}
      {:ok, %Change{book: book, auction: auction, action: :started, cost: cost}}
    end
  end

  def bid(%Book{} = book, %Actor{} = actor, %House{} = house, id, price, now) when is_integer(now) do
    with {:ok, auction} <- find(book, house, id, now),
         :ok <- validate_bid(auction, actor, price),
         amount = bid_amount(auction, price),
         cost = amount - if(auction.bidder == actor.guid, do: auction.bid, else: 0),
         :ok <- funds(actor, cost) do
      {deliveries, notices} = outbid(auction, actor.guid, now)
      auction = %{auction | bidder: actor.guid, bid: amount, revision: auction.revision + 1}
      change = %Change{book: book, auction: auction, action: :bid_placed, cost: cost}

      change =
        if auction.buyout > 0 and amount == auction.buyout do
          settle(change, auction, now)
        else
          book = %{book | auctions: Map.put(book.auctions, auction.id, auction)}
          %{change | book: book, notices: [notice(auction, auction.owner, :bid_received)]}
        end

      {:ok, %{change | deliveries: deliveries ++ change.deliveries, notices: notices ++ change.notices}}
    end
  end

  def cancel(%Book{} = book, %Actor{} = actor, %House{} = house, id, now) when is_integer(now) do
    with {:ok, auction} <- find(book, house, id, now),
         :ok <- owner(auction, actor),
         cost = if(auction.bidder > 0, do: cut(auction), else: 0),
         :ok <- funds(actor, cost) do
      deliveries = [Settlement.returned(auction, :canceled, now)]

      {deliveries, notices} =
        if auction.bidder > 0 do
          {[Settlement.refund(auction, :canceled_to_bidder, now) | deliveries],
           [notice(auction, auction.bidder, :removed)]}
        else
          {deliveries, []}
        end

      {:ok,
       %Change{
         book: remove(book, auction),
         auction: auction,
         action: :removed,
         cost: cost,
         deliveries: deliveries,
         notices: notices
       }}
    end
  end

  def expire(%Book{} = book, now) when is_integer(now) do
    book.auctions
    |> Map.values()
    |> Enum.filter(&(&1.expires_at <= now))
    |> Enum.sort_by(&{&1.expires_at, &1.id})
    |> Enum.reduce(%Change{book: book}, &settle(&2, &1, now))
  end

  def next_expiration(%Book{auctions: auctions}) do
    auctions |> Map.values() |> Enum.map(& &1.expires_at) |> Enum.min(fn -> nil end)
  end

  defp settle(%Change{} = change, %Auction{bidder: 0} = auction, now) do
    %{
      change
      | book: remove(change.book, auction),
        deliveries: change.deliveries ++ [Settlement.returned(auction, :expired, now)],
        notices: change.notices ++ [notice(auction, auction.owner, :expired)]
    }
  end

  defp settle(%Change{} = change, %Auction{} = auction, now) do
    %{
      change
      | book: remove(change.book, auction),
        deliveries: change.deliveries ++ Settlement.sold(auction, cut(auction), now),
        notices: change.notices ++ [notice(auction, auction.owner, :sold), notice(auction, auction.bidder, :won)]
    }
  end

  defp outbid(%Auction{bidder: previous} = auction, bidder, now) when previous > 0 and previous != bidder do
    {[Settlement.refund(auction, :outbid, now)], [notice(auction, previous, :outbid)]}
  end

  defp outbid(_auction, _bidder, _now), do: {[], []}

  defp bid_amount(%Auction{buyout: buyout}, price) when buyout > 0, do: min(price, buyout)
  defp bid_amount(_auction, price), do: price

  defp find(%Book{auctions: auctions}, %House{market: market}, id, now) do
    case Map.get(auctions, id) do
      %Auction{house: %House{market: ^market}, expires_at: expires_at} = auction when expires_at > now ->
        {:ok, auction}

      _ ->
        {:error, :item_not_found}
    end
  end

  defp validate_terms(%{start_bid: bid, buyout: buyout, duration_minutes: duration}) do
    cond do
      not valid_price?(bid) or not is_integer(buyout) or buyout < 0 or buyout > @maximum_price ->
        {:error, :invalid_price}

      buyout > 0 and bid > buyout ->
        {:error, :higher_bid}

      duration not in @durations ->
        {:error, :invalid_duration}

      true ->
        :ok
    end
  end

  defp validate_terms(_terms), do: {:error, :invalid_price}

  defp sale_item(%Book{auctions: auctions}, %Actor{guid: guid}, %Item{} = item) do
    if item.item.owner == guid and
         not Enum.any?(auctions, fn {_id, auction} -> auction.item.object.guid == item.object.guid end),
       do: :ok,
       else: {:error, :item_not_found}
  end

  defp validate_bid(%Auction{} = auction, %Actor{} = actor, price) do
    cond do
      auction.owner == actor.guid or auction.owner_account == actor.account_id -> {:error, :bid_own}
      not valid_price?(price) -> {:error, :invalid_price}
      price < auction.start_bid -> {:error, :bid_increment}
      price <= auction.bid -> {:error, {:higher_bid, auction}}
      below_increment?(auction, price) -> {:error, :bid_increment}
      true -> :ok
    end
  end

  defp below_increment?(%Auction{} = auction, price) do
    (auction.buyout == 0 or price < auction.buyout) and price < auction.bid + increment(auction)
  end

  defp valid_price?(price), do: is_integer(price) and price > 0 and price <= @maximum_price
  defp funds(%Actor{money: money}, cost) when money >= cost, do: :ok
  defp funds(_actor, _cost), do: {:error, :not_enough_money}
  defp owner(%Auction{owner: guid}, %Actor{guid: guid}), do: :ok
  defp owner(_auction, _actor), do: {:error, :not_owner}
  defp remove(%Book{} = book, %Auction{id: id}), do: %{book | auctions: Map.delete(book.auctions, id)}
  defp notice(auction, recipient, kind), do: %Notice{auction: auction, recipient: recipient, kind: kind}
end
