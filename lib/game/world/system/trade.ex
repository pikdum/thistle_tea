defmodule ThistleTea.Game.World.System.Trade do
  @moduledoc """
  Owns trade negotiations. Both player owners freeze their inventory snapshots
  before the single atomic item-store commit; each owner applies its receipt.
  """
  use GenServer

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Trade
  alias ThistleTea.Game.Entity.Data.Trade.Decision
  alias ThistleTea.Game.Entity.Data.Trade.Prepare
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Trade, as: TradeLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgAreaTriggerMessage
  alias ThistleTea.Game.Network.Message.SmsgTradeStatus
  alias ThistleTea.Game.Network.Message.SmsgTradeStatusExtended
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment
  alias ThistleTea.Game.World.Metadata

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def request(guid, action, server \\ __MODULE__), do: GenServer.call(server, {:request, guid, action})
  def cancel(guid, server \\ __MODULE__), do: GenServer.cast(server, {:cancel, guid})

  def prepared(server, id, character, old_counts) do
    GenServer.call(server, {:prepared, id, character, old_counts})
  end

  def abort(server, id, guid), do: GenServer.call(server, {:abort, id, guid})

  @impl true
  def init(opts) do
    Process.send_after(self(), :check, 250)

    {:ok,
     %{
       sessions: %{},
       players: %{},
       position: Keyword.get(opts, :position, &World.position/1),
       metadata: Keyword.get(opts, :metadata, &Metadata.query(&1, [:race, :alive?, :unit_flags])),
       owner: Keyword.get(opts, :owner, &Entity.pid/1),
       packet: Keyword.get(opts, :packet, &Network.send_packet/2),
       now: Keyword.get(opts, :now, &Time.now/0),
       get_item: Keyword.get(opts, :get_item, &ItemStore.get/1),
       get_enchantment: Keyword.get(opts, :get_enchantment, &ItemEnchantment.get/1)
     }}
  end

  @impl true
  def handle_call({:request, guid, action}, {owner, _tag}, state) do
    {reply, state} = handle_request(state, guid, owner, action)
    {:reply, reply, state}
  rescue
    error ->
      Logger.error("Trade request failed: #{Exception.message(error)}")
      {:reply, {:error, :trade_canceled}, cancel_player(state, guid)}
  end

  def handle_call({:prepared, id, character, old_counts}, {owner, _tag}, state) do
    guid = character.object.guid

    case Map.get(state.sessions, id) do
      %{trade: %Trade{phase: :preparing}, pids: %{^guid => ^owner}} = session ->
        prepared = Map.put(session.prepared, guid, {character, old_counts})
        session = %{session | prepared: prepared}
        state = put_session(state, session)
        state = if map_size(prepared) == 2, do: complete(state, session), else: state
        {:reply, :ok, state}

      _ ->
        {:reply, :stale, state}
    end
  rescue
    error ->
      Logger.error("Trade preparation failed: #{Exception.message(error)}")
      {:reply, :stale, cancel_session(state, id)}
  end

  def handle_call({:abort, id, guid}, _from, state) do
    state = if Map.get(state.players, guid) == id, do: cancel_session(state, id), else: state
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:cancel, guid}, state), do: {:noreply, cancel_player(state, guid)}

  @impl true
  def handle_info(:check, state) do
    state =
      Enum.reduce(state.sessions, state, fn {id, session}, state ->
        if valid_pair?(state, session.trade), do: state, else: cancel_session(state, id)
      end)

    Process.send_after(self(), :check, 250)
    {:noreply, state}
  end

  def handle_info({:prepare_timeout, id}, state), do: {:noreply, cancel_session(state, id)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state =
      Enum.reduce(state.sessions, state, fn {id, session}, state ->
        if ref in session.monitors, do: cancel_session(state, id), else: state
      end)

    {:noreply, state}
  end

  defp handle_request(state, guid, owner, {:initiate, target}) do
    with :ok <- available(state, guid, target),
         true <- state.owner.(guid) == owner,
         target_owner when is_pid(target_owner) <- state.owner.(target),
         :ok <- admission(state, guid, target) do
      trade = TradeLogic.new(make_ref(), guid, target, state.now.())
      pids = %{guid => owner, target => target_owner}

      session = %{
        trade: trade,
        pids: pids,
        monitors: Enum.map(Map.values(pids), &Process.monitor/1),
        prepared: %{},
        timer: nil
      }

      state = %{
        put_session(state, session)
        | players: Map.merge(state.players, %{guid => trade.id, target => trade.id})
      }

      state.packet.(%SmsgTradeStatus{status: :begin_trade, player_guid: guid}, target)
      {:ok, state}
    else
      {:error, reason} -> {{:error, reason}, state}
      _ -> {{:error, :no_target}, state}
    end
  end

  defp handle_request(state, guid, owner, action) do
    with id when not is_nil(id) <- Map.get(state.players, guid),
         %{pids: %{^guid => ^owner}} = session <- Map.get(state.sessions, id) do
      update(state, session, guid, action)
    else
      _ -> {:ok, state}
    end
  end

  defp update(state, session, guid, :open) do
    case TradeLogic.open(session.trade, guid) do
      {:ok, trade} ->
        status_both(state, trade, :open_window)
        publish(state, trade)
        {:ok, put_session(state, %{session | trade: trade})}

      error ->
        edit_error(state, session, error)
    end
  end

  defp update(state, session, _guid, {:cancel, reason}) do
    {:ok, cancel_session(state, session.trade.id, reason)}
  end

  defp update(state, session, guid, :accept) do
    case TradeLogic.accept(session.trade, guid, state.now.()) do
      {:ok, trade} ->
        state.packet.(%SmsgTradeStatus{status: :trade_accept}, TradeLogic.other(trade, guid))
        session = begin_preparation(%{session | trade: trade})

        {:ok, put_session(state, session)}

      error ->
        edit_error(state, session, error)
    end
  end

  defp update(state, session, guid, action) do
    case edit(session.trade, guid, action, state.now.()) do
      {:ok, trade} ->
        status_both(state, trade, :back_to_trade)
        publish(state, trade)
        {:ok, put_session(state, %{session | trade: trade})}

      error ->
        edit_error(state, session, error)
    end
  end

  defp edit_error(state, session, {:error, :trade_canceled}) do
    {:ok, cancel_session(state, session.trade.id)}
  end

  defp edit_error(state, _session, error), do: {error, state}

  defp begin_preparation(%{trade: %Trade{phase: :preparing, id: id}} = session) do
    Enum.each(session.pids, fn {_guid, pid} -> send(pid, %Prepare{id: id, coordinator: self()}) end)
    %{session | timer: Process.send_after(self(), {:prepare_timeout, id}, 2_000)}
  end

  defp begin_preparation(session), do: session

  defp edit(trade, guid, {:money, amount}, now), do: TradeLogic.money(trade, guid, amount, now)
  defp edit(trade, guid, {:item, slot, item}, now), do: TradeLogic.put_item(trade, guid, slot, item, now)
  defp edit(trade, guid, {:clear, slot}, now), do: TradeLogic.clear_item(trade, guid, slot, now)
  defp edit(trade, guid, :unaccept, _now), do: TradeLogic.unaccept(trade, guid)

  defp complete(state, session) do
    characters = Map.new(session.prepared, fn {guid, {character, _counts}} -> {guid, character} end)
    counts = Map.new(session.prepared, fn {guid, {_character, counts}} -> {guid, counts} end)

    result =
      if valid_pair?(state, session.trade),
        do: TradeLogic.plan(session.trade, characters, state.now.(), state.get_item, state.get_enchantment),
        else: {:error, session.trade.initiator, :item_not_found}

    case result do
      {:ok, exchange} ->
        ItemStore.commit_trade(exchange, counts)
        release(session)
        remove_session(state, session)

      {:error, guid, :too_much_gold} ->
        state.packet.(%SmsgAreaTriggerMessage{message: "You cannot carry any more gold."}, guid)
        cancel_session(state, session.trade.id)

      {:error, guid, reason} ->
        Enum.each(TradeLogic.participants(session.trade), fn participant ->
          state.packet.(
            %SmsgTradeStatus{
              status: :close_window,
              inventory_result: Inventory.error_code(reason),
              target_error: participant != guid
            },
            participant
          )
        end)

        release(session)
        remove_session(state, session)
    end
  end

  defp available(state, guid, target) do
    if guid == target or Map.has_key?(state.players, guid) or Map.has_key?(state.players, target) or
         not is_nil(ItemStore.pending_trade(guid)) or not is_nil(ItemStore.pending_trade(target)),
       do: {:error, :busy},
       else: :ok
  end

  defp admission(state, guid, target) do
    own = state.metadata.(guid)
    other = state.metadata.(target)

    cond do
      is_nil(own) or is_nil(other) -> {:error, :no_target}
      other[:alive?] != true -> {:error, :target_dead}
      flag?(other, 0x40000) -> {:error, :target_stunned}
      flag?(other, 0x100000) -> {:error, :target_to_far}
      not Party.same_team?(own[:race], other[:race]) -> {:error, :wrong_faction}
      not near?(state.position.(guid), state.position.(target)) -> {:error, :target_to_far}
      true -> :ok
    end
  end

  defp flag?(metadata, flag), do: ((metadata[:unit_flags] || 0) &&& flag) != 0

  defp valid_pair?(state, trade) do
    admission(state, trade.initiator, trade.recipient) == :ok and
      admission(state, trade.recipient, trade.initiator) == :ok and offers_current?(state, trade)
  end

  defp offers_current?(state, trade) do
    Enum.all?(trade.offers, fn {_guid, offer} ->
      Enum.all?(offer.items, fn {_slot, item} -> state.get_item.(item.object.guid) == item end)
    end)
  end

  defp near?({world, x, y, z}, {world, a, b, c}), do: (x - a) ** 2 + (y - b) ** 2 + (z - c) ** 2 <= 100
  defp near?(_first, _second), do: false

  defp publish(state, trade) do
    Enum.each(trade.offers, fn {guid, offer} ->
      Enum.each(TradeLogic.participants(trade), fn receiver ->
        state.packet.(
          %SmsgTradeStatusExtended{other?: receiver != guid, money: offer.money, items: offer.items},
          receiver
        )
      end)
    end)
  end

  defp status_both(state, trade, status) do
    Enum.each(TradeLogic.participants(trade), &state.packet.(%SmsgTradeStatus{status: status}, &1))
  end

  defp put_session(state, session), do: %{state | sessions: Map.put(state.sessions, session.trade.id, session)}

  defp cancel_player(state, guid) do
    cancel_session(state, Map.get(state.players, guid))
  end

  defp cancel_session(state, id, status \\ :trade_canceled) do
    case Map.get(state.sessions, id) do
      nil ->
        state

      session ->
        status_both(state, session.trade, status)
        release(session)
        remove_session(state, session)
    end
  end

  defp release(session) do
    Enum.each(session.pids, fn {_guid, pid} -> send(pid, %Decision{id: session.trade.id}) end)
  end

  defp remove_session(state, session) do
    Enum.each(session.monitors, &Process.demonitor(&1, [:flush]))
    if session.timer, do: Process.cancel_timer(session.timer)

    %{
      state
      | sessions: Map.delete(state.sessions, session.trade.id),
        players: Map.drop(state.players, TradeLogic.participants(session.trade))
    }
  end
end
