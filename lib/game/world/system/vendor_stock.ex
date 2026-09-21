defmodule ThistleTea.Game.World.System.VendorStock do
  @moduledoc """
  Serializes stock checks and committed purchases across merchant customers.
  The caller keeps ownership of the player and applies its committed receipt.
  """

  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.VendorStock.Receipt
  alias ThistleTea.Game.Entity.Logic.VendorStock, as: Stock
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.VendorStockStore

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def list(world, guid, items, server \\ __MODULE__) do
    GenServer.call(server, {:list, world, guid, items})
  end

  def purchase(world, %Receipt{} = receipt, server \\ __MODULE__) do
    GenServer.call(server, {:purchase, world, receipt}, :infinity)
  end

  def clear_world(world, server \\ __MODULE__), do: GenServer.call(server, {:clear_world, world})

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       table: Keyword.get(opts, :table, ItemStore),
       now: Keyword.get(opts, :now, &Time.now/0),
       owner: Keyword.get(opts, :owner, &Entity.pid/1),
       random: Keyword.get(opts, :random, fn -> :rand.uniform(41) + 79 end),
       population: Keyword.get(opts, :population, fn -> :ets.info(:session, :size) end)
     }}
  end

  @impl GenServer
  def handle_call({:clear_world, world}, _from, state) do
    :ok = VendorStockStore.clear_world(world, state.table)
    {:reply, :ok, state}
  rescue
    error ->
      Logger.error("Vendor stock cleanup failed: #{Exception.message(error)}")
      {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:list, world, guid, items}, _from, state) do
    now = state.now.()

    items =
      Enum.map(items, fn item ->
        key = {world, guid, item.template.entry}
        {available, stock} = Stock.current(VendorStockStore.stock(key, state.table), item, now)
        VendorStockStore.put(key, stock, state.table)
        %{item | available: available}
      end)

    {:reply, items, state}
  rescue
    error ->
      Logger.error("Vendor stock listing failed: #{Exception.message(error)}")
      {:reply, [], state}
  end

  def handle_call({:purchase, world, %Receipt{} = receipt}, {pid, _tag}, state) do
    result =
      cond do
        state.owner.(receipt.guid) != pid -> {:error, :not_owner}
        VendorStockStore.pending(receipt.guid, state.table) != nil -> {:error, :pending_receipt}
        true -> commit(state, world, receipt)
      end

    {:reply, result, state}
  rescue
    error ->
      Logger.error("Vendor purchase failed: #{Exception.message(error)}")
      {:reply, {:error, :unavailable}, state}
  end

  defp commit(state, world, receipt) do
    item = receipt.vendor_item
    key = {world, receipt.vendor_guid, item.template.entry}
    stock = VendorStockStore.stock(key, state.table)
    delay = Stock.restock_delay(item, state.random.(), state.population.())
    count = receipt.count * max(item.template.buy_count, 1)

    case Stock.purchase(stock, item, count, state.now.(), delay) do
      {:ok, available, stock} ->
        receipt = %{receipt | available: available}
        :ok = VendorStockStore.commit(key, stock, receipt, state.table)
        {:ok, receipt}

      {:error, reason, stock} ->
        VendorStockStore.put(key, stock, state.table)
        {:error, reason}
    end
  end
end
