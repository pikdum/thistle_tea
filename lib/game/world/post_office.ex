defmodule ThistleTea.Game.World.PostOffice do
  @moduledoc """
  Mailbox custody boundary. It assigns mail ids and retains each delivery
  until an online player acknowledges it. Opening and closing a mailbox moves
  custody between this process and the character process without duplicating
  a second authoritative mailbox.
  """

  use GenServer

  alias ThistleTea.Game.Entity.Data.Mail
  alias ThistleTea.Game.Entity.Logic.Mail, as: MailLogic
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.MailStore

  def start_link(opts \\ []) do
    {table, opts} = Keyword.pop(opts, :table)
    opts = Keyword.put_new(opts, :name, __MODULE__)
    table = table || if(Keyword.get(opts, :name) == __MODULE__, do: MailStore)
    GenServer.start_link(__MODULE__, table, opts)
  end

  def post(attrs, server \\ __MODULE__) when is_map(attrs), do: GenServer.call(server, {:post, attrs})

  def post_once(key, attrs, server \\ __MODULE__) when is_map(attrs) do
    GenServer.call(server, {:post_once, key, attrs})
  end

  def pending?(recipient, token, id, server \\ __MODULE__) do
    GenServer.call(server, {:pending, recipient, token, id})
  end

  def open(recipient, pid \\ self(), server \\ __MODULE__) when is_integer(recipient) and is_pid(pid) do
    GenServer.call(server, {:open, recipient, pid})
  end

  def acknowledge(recipient, token, ids, server \\ __MODULE__) when is_list(ids) do
    GenServer.call(server, {:acknowledge, recipient, token, ids})
  end

  def close(recipient, token, mailbox, server \\ __MODULE__) when is_list(mailbox) do
    GenServer.call(server, {:close, recipient, token, mailbox})
  end

  @impl GenServer
  def init(table) do
    table = table || :ets.new(MailStore, [:public])
    send(self(), :redeliver)
    {:ok, Map.put(MailStore.load(table), :table, table)}
  end

  @impl GenServer
  def handle_call({:post, attrs}, _from, state) do
    {mail, state} = prepare_mail(state, attrs)
    state = persist(state)
    notify_online(state.online, mail)
    {:reply, {:ok, mail}, state}
  rescue
    _error -> {:reply, {:error, :invalid_mail}, state}
  end

  def handle_call({:post_once, key, attrs}, _from, state) do
    case Map.fetch(state.posted, key) do
      {:ok, mail} ->
        {:reply, {:ok, mail}, state}

      :error ->
        {mail, state} = prepare_mail(state, attrs)
        state = persist(%{state | posted: Map.put(state.posted, key, mail)})
        notify_online(state.online, mail)
        {:reply, {:ok, mail}, state}
    end
  rescue
    _error -> {:reply, {:error, :invalid_mail}, state}
  end

  def handle_call({:pending, recipient, token, id}, _from, state) do
    pending =
      match?({_pid, ^token}, Map.get(state.online, recipient)) and
        Enum.any?(Map.get(state.mailboxes, recipient, []), &(&1.id == id))

    {:reply, pending, state}
  end

  def handle_call({:open, recipient, pid}, _from, state) do
    token = make_ref()
    mailbox = Map.get(state.mailboxes, recipient, [])
    online = Map.put(state.online, recipient, {pid, token})
    {:reply, {token, mailbox}, persist(%{state | online: online})}
  end

  def handle_call({:close, recipient, token, mailbox}, _from, state) do
    case Map.get(state.online, recipient) do
      {_pid, ^token} ->
        pending = Map.get(state.mailboxes, recipient, [])
        mailboxes = Map.put(state.mailboxes, recipient, MailLogic.merge(mailbox, pending))
        {:reply, :ok, persist(%{state | mailboxes: mailboxes, online: Map.delete(state.online, recipient)})}

      _ ->
        {:reply, {:error, :stale_session}, state}
    end
  end

  def handle_call({:acknowledge, recipient, token, ids}, _from, state) do
    state =
      case Map.get(state.online, recipient) do
        {_pid, ^token} ->
          mailbox = Enum.reject(Map.get(state.mailboxes, recipient, []), &(&1.id in ids))
          %{state | mailboxes: Map.put(state.mailboxes, recipient, mailbox)}

        _ ->
          state
      end

    {:reply, :ok, persist(state)}
  end

  @impl GenServer
  def handle_info(:redeliver, state) do
    for {_recipient, mails} <- state.mailboxes, mail <- mails, do: notify_online(state.online, mail)
    {:noreply, state}
  end

  defp prepare_mail(state, attrs) do
    mail = attrs |> Map.put(:id, state.next_id) |> MailLogic.new(Time.now())
    mailbox = state.mailboxes |> Map.get(mail.receiver, []) |> MailLogic.add(mail)
    {mail, %{state | next_id: state.next_id + 1, mailboxes: Map.put(state.mailboxes, mail.receiver, mailbox)}}
  end

  defp persist(state) do
    MailStore.save(Map.delete(state, :table), state.table)
    state
  end

  defp notify_online(online, %Mail{receiver: recipient} = mail) do
    case Map.get(online, recipient) do
      {pid, token} -> GenServer.cast(pid, {:mail_delivery, token, mail})
      nil -> :ok
    end
  end
end
