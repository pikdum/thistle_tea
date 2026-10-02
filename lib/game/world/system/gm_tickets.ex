defmodule ThistleTea.Game.World.System.GmTickets do
  @moduledoc """
  Owns the open help tickets, one per character, and the queue facts the help
  frame shows: the oldest open ticket and the last change to the queue.
  Characters file, edit, and abandon their own tickets; answering one
  completes it and tells its owner if they are online.
  """

  use GenServer

  alias ThistleTea.Game.Core.GmTicket
  alias ThistleTea.Game.Core.Time

  require Logger

  defmodule Queue do
    @moduledoc false
    defstruct tickets: %{}, next_id: 1, last_change: nil
  end

  defmodule View do
    @moduledoc false
    @enforce_keys [:ticket]
    defstruct [:ticket, :oldest_at, :last_change]
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def view(player_guid, server \\ __MODULE__), do: call(server, {:view, player_guid}, nil)

  def create(player_guid, player_name, type, message, map_id, position, now \\ Time.now(), server \\ __MODULE__),
    do: call(server, {:create, player_guid, player_name, type, message, map_id, position, now}, :error)

  def update_text(player_guid, type, message, now \\ Time.now(), server \\ __MODULE__),
    do: call(server, {:update_text, player_guid, type, message, now}, :error)

  def abandon(player_guid, server \\ __MODULE__), do: call(server, {:abandon, player_guid}, :none)

  def respond(id, response, now \\ Time.now(), server \\ __MODULE__),
    do: call(server, {:respond, id, response, now}, :none)

  def list(server \\ __MODULE__), do: call(server, :list, [])

  defp call(server, request, fallback) do
    GenServer.call(server, request)
  catch
    :exit, reason ->
      Logger.warning("GM ticket queue unavailable: #{inspect(reason)}")
      fallback
  end

  @impl GenServer
  def init(_opts), do: {:ok, %Queue{}}

  @impl GenServer
  def handle_call({:view, player_guid}, _from, queue), do: {:reply, view_of(queue, player_guid), queue}

  def handle_call({:create, player_guid, name, type, message, map_id, position, now}, _from, queue) do
    case Map.get(queue.tickets, player_guid) do
      %GmTicket{completed?: false} ->
        {:reply, :exists, queue}

      _none_or_completed ->
        ticket = GmTicket.new(queue.next_id, player_guid, name, type, message, map_id, position, now)
        tickets = Map.put(queue.tickets, player_guid, ticket)
        queue = %{queue | tickets: tickets, next_id: queue.next_id + 1, last_change: now}
        Logger.info("GM ticket ##{ticket.id} opened by #{name}: #{message}")
        {:reply, {:ok, ticket}, queue}
    end
  end

  def handle_call({:update_text, player_guid, type, message, now}, _from, queue) do
    with %GmTicket{completed?: false} = ticket <- Map.get(queue.tickets, player_guid),
         {:ok, ticket} <- GmTicket.update_text(ticket, type, message, now) do
      {:reply, {:ok, ticket}, %{queue | tickets: Map.put(queue.tickets, player_guid, ticket), last_change: now}}
    else
      %GmTicket{completed?: true} = ticket -> {:reply, {:completed, ticket}, queue}
      _missing_or_invalid -> {:reply, :error, queue}
    end
  end

  def handle_call({:abandon, player_guid}, _from, queue) do
    case Map.pop(queue.tickets, player_guid) do
      {%GmTicket{}, tickets} -> {:reply, :ok, %{queue | tickets: tickets}}
      {nil, _tickets} -> {:reply, :none, queue}
    end
  end

  def handle_call({:respond, id, response, now}, _from, queue) do
    case Enum.find(Map.values(queue.tickets), &(&1.id == id)) do
      %GmTicket{player_guid: guid} = ticket ->
        ticket = GmTicket.respond(ticket, response, now)
        {:reply, {:ok, ticket}, %{queue | tickets: Map.put(queue.tickets, guid, ticket), last_change: now}}

      nil ->
        {:reply, :none, queue}
    end
  end

  def handle_call(:list, _from, queue), do: {:reply, Enum.sort_by(Map.values(queue.tickets), & &1.id), queue}

  defp view_of(queue, player_guid) do
    case Map.get(queue.tickets, player_guid) do
      %GmTicket{} = ticket -> %View{ticket: ticket, oldest_at: oldest_at(queue), last_change: queue.last_change}
      nil -> nil
    end
  end

  defp oldest_at(queue) do
    queue.tickets
    |> Map.values()
    |> Enum.reject(& &1.completed?)
    |> Enum.map(& &1.modified_at)
    |> Enum.min(fn -> nil end)
  end
end
