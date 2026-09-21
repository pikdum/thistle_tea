defmodule ThistleTea.Game.World.System.Auction do
  @moduledoc """
  Serializes auction requests and deadline settlement. The caller remains
  blocked while its inventory snapshot is planned and committed, then applies
  its receipt locally. Deliveries retry through the idempotent Post Office.
  """
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Auction.Actor
  alias ThistleTea.Game.Entity.Data.Auction.Receipt
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Auction, as: AuctionLogic
  alias ThistleTea.Game.Entity.Logic.Auction.Inventory, as: AuctionInventory
  alias ThistleTea.Game.Entity.Logic.Auction.Query
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.AuctionStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment
  alias ThistleTea.Game.World.PostOffice

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def transact(%Character{} = character, house, request, old_counts, server \\ __MODULE__) do
    GenServer.call(server, {:transact, character, house, request, old_counts}, :infinity)
  end

  def list(house, request, server \\ __MODULE__), do: GenServer.call(server, {:list, house, request})

  def settle(server \\ __MODULE__), do: GenServer.call(server, :settle)

  def debug_expire(guid, id, server \\ __MODULE__), do: GenServer.call(server, {:debug_expire, guid, id}, :infinity)

  @impl GenServer
  def init(opts) do
    state = %{
      table: Keyword.get(opts, :table, ItemStore),
      now: Keyword.get(opts, :now, &Time.now/0),
      owner: Keyword.get(opts, :owner, &Entity.pid/1),
      enchantment: Keyword.get(opts, :enchantment, &ItemEnchantment.get/1),
      post: Keyword.get(opts, :post, &PostOffice.post_once/2),
      notify: Keyword.get(opts, :notify, &notify/1),
      timer: nil
    }

    send(self(), :settle)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:transact, character, house, request, old_counts}, {pid, _tag}, state) do
    state = advance(state)
    guid = character.object.guid

    result =
      with true <- state.owner.(guid) == pid,
           nil <- AuctionStore.pending(guid, state.table),
           {:ok, change} <- propose(state, character, house, request),
           {:ok, changes} <- AuctionInventory.plan(character, change, &AuctionStore.item(&1, state.table)) do
        receipt = %Receipt{
          id: make_ref(),
          guid: guid,
          changes: changes,
          old_counts: old_counts,
          outgoing: if(change.action == :started, do: [change.auction.item.object.guid], else: []),
          action: change.action,
          auction: change.auction
        }

        AuctionStore.commit(change, receipt, state.table)
        Enum.each(change.notices, state.notify)
        {:ok, receipt}
      else
        false -> {:error, :not_owner}
        %Receipt{} -> {:error, :pending_receipt}
        error -> error
      end

    {:reply, result, finish(state)}
  rescue
    error ->
      Logger.error("Auction request failed: #{Exception.message(error)}")
      {:reply, {:error, :database}, schedule(state)}
  end

  def handle_call({:list, house, request}, _from, state) do
    state = advance(state)
    result = query(AuctionStore.book(state.table), house, request, state.now.())
    {:reply, result, state}
  rescue
    error ->
      Logger.error("Auction listing failed: #{Exception.message(error)}")
      {:reply, {[], 0}, schedule(state)}
  end

  def handle_call(:settle, _from, state) do
    {:reply, :ok, advance(state)}
  rescue
    error ->
      Logger.error("Auction settlement failed: #{Exception.message(error)}")
      {:reply, {:error, :database}, schedule(state)}
  end

  def handle_call({:debug_expire, guid, id}, {pid, _tag}, state) do
    book = AuctionStore.book(state.table)

    with true <- state.owner.(guid) == pid,
         %{owner: ^guid} = auction <- Map.get(book.auctions, id) do
      now = state.now.()
      auction = %{auction | expires_at: now}
      book = %{book | auctions: Map.put(book.auctions, id, auction)}
      change = AuctionLogic.expire(book, now)
      AuctionStore.commit(change, nil, state.table)
      Enum.each(change.notices, state.notify)
      {:reply, :ok, finish(state)}
    else
      _ -> {:reply, {:error, :not_owner}, state}
    end
  rescue
    error ->
      Logger.error("Auction expiry command failed: #{Exception.message(error)}")
      {:reply, {:error, :database}, schedule(state)}
  end

  @impl GenServer
  def handle_info(:settle, state) do
    {:noreply, advance(state)}
  rescue
    error ->
      Logger.error("Auction settlement failed: #{Exception.message(error)}")
      {:noreply, schedule(state)}
  end

  defp propose(state, character, house, request) do
    actor = %Actor{guid: character.object.guid, account_id: character.account_id, money: character.player.coinage}
    book = AuctionStore.book(state.table)
    now = state.now.()

    case request do
      {:sell, guid, terms} -> sell(state, character, book, actor, house, guid, terms, now)
      {:bid, id, amount} -> AuctionLogic.bid(book, actor, house, id, amount, now)
      {:cancel, id} -> AuctionLogic.cancel(book, actor, house, id, now)
    end
  end

  defp sell(state, character, book, actor, house, guid, terms, now) do
    with %Item{} = item <- AuctionStore.item(guid, state.table),
         :ok <-
           AuctionInventory.validate_sale(character, item, now, &AuctionStore.item(&1, state.table), state.enchantment) do
      AuctionLogic.sell(book, actor, house, item, terms, now)
    else
      nil -> {:error, :item_not_found}
      error -> error
    end
  end

  defp query(book, house, {:search, query, opts}, now), do: Query.search(book, house, query, now, opts)
  defp query(book, house, {:owned, guid, offset}, now), do: Query.owned(book, house, guid, offset, now)
  defp query(book, house, {:bids, guid, ids, offset}, now), do: Query.bids(book, house, guid, ids, offset, now)

  defp advance(state) do
    book = AuctionStore.book(state.table)
    change = AuctionLogic.expire(book, state.now.())

    if change.book != book do
      AuctionStore.commit(change, nil, state.table)
      Enum.each(change.notices, state.notify)
    end

    finish(state)
  end

  defp finish(state) do
    Enum.each(AuctionStore.deliveries(state.table), fn delivery ->
      case post(state, delivery) do
        {:ok, _mail} -> AuctionStore.delivered(delivery, state.table)
        _error -> :ok
      end
    end)

    schedule(state)
  end

  defp post(state, delivery) do
    state.post.(delivery.key, delivery.attrs)
  rescue
    _error -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp schedule(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    deadline = AuctionLogic.next_expiration(AuctionStore.book(state.table))
    delay = if deadline, do: max(deadline - state.now.(), 0)
    delay = if AuctionStore.deliveries(state.table) == [], do: delay, else: min(delay || 1_000, 1_000)
    timer = if delay, do: Process.send_after(self(), :settle, delay)
    %{state | timer: timer}
  end

  defp notify(notice) do
    case Entity.pid(notice.recipient) do
      pid when is_pid(pid) -> GenServer.cast(pid, {:auction_notice, notice})
      _ -> :ok
    end
  end
end
