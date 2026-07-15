defmodule ThistleTea.Game.Entity.Logic.Mail do
  @moduledoc """
  Pure mailbox and mail-state transitions. Delivery routing, item storage and
  packet emission are boundary concerns.
  """

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Mail

  @postage 30
  @delivery_delay_ms to_timeout(hour: 1)
  @expiration_ms to_timeout(day: 30)
  @cod_expiration_ms to_timeout(day: 3)
  @read_expiration_ms to_timeout(day: 3)
  @max_visible 254

  @checked_read 0x01
  @checked_returned 0x02
  @checked_copied 0x04
  @checked_cod_payment 0x08
  @checked_has_body 0x10

  def postage, do: @postage
  def delivery_delay_ms, do: @delivery_delay_ms
  def checked_returned, do: @checked_returned
  def checked_copied, do: @checked_copied
  def checked_cod_payment, do: @checked_cod_payment

  def new(attrs, now) when is_map(attrs) and is_integer(now) do
    mail = struct!(Mail, attrs)
    validate!(mail)
    deliver_at = mail.deliver_at || now + delivery_delay(mail)
    expire_at = mail.expire_at || deliver_at + expiration(mail)
    checked = if mail.body == "", do: mail.checked, else: mail.checked ||| @checked_has_body
    %{mail | deliver_at: deliver_at, expire_at: expire_at, checked: checked}
  end

  def add(mailbox, %Mail{id: id} = mail) when is_list(mailbox) and is_integer(id) do
    mailbox
    |> Enum.reject(&(&1.id == id))
    |> then(&[mail | &1])
    |> Enum.sort_by(&{&1.deliver_at, &1.id})
  end

  def merge(mailbox, mails) when is_list(mailbox) and is_list(mails) do
    Enum.reduce(mails, mailbox, &add(&2, &1))
  end

  def visible(mailbox, now) when is_list(mailbox) and is_integer(now) do
    mailbox
    |> Enum.filter(&visible?(&1, now))
    |> Enum.take(@max_visible)
  end

  def visible?(%Mail{} = mail, now) when is_integer(now) do
    mail.deliver_at <= now and mail.expire_at > now
  end

  def unread?(%Mail{} = mail, now) when is_integer(now) do
    visible?(mail, now) and (mail.checked &&& @checked_read) == 0
  end

  def has_unread?(mailbox, now), do: Enum.any?(mailbox, &unread?(&1, now))

  def next_delivery(mailbox, now) when is_list(mailbox) and is_integer(now) do
    mailbox
    |> Enum.filter(&(&1.deliver_at > now and &1.expire_at > &1.deliver_at))
    |> Enum.map(& &1.deliver_at)
    |> Enum.min(fn -> nil end)
  end

  def find(mailbox, id) when is_list(mailbox) and is_integer(id), do: Enum.find(mailbox, &(&1.id == id))

  def replace(mailbox, %Mail{id: id} = mail) when is_list(mailbox) do
    Enum.map(mailbox, fn
      %Mail{id: ^id} -> mail
      other -> other
    end)
  end

  def remove(mailbox, id) when is_list(mailbox) and is_integer(id), do: Enum.reject(mailbox, &(&1.id == id))

  def mark_read(%Mail{} = mail, now) when is_integer(now) do
    %{mail | checked: mail.checked ||| @checked_read, expire_at: min(mail.expire_at, now + @read_expiration_ms)}
  end

  def take_money(%Mail{money: money} = mail) when money > 0, do: {:ok, money, %{mail | money: 0}}
  def take_money(%Mail{}), do: {:error, :no_money}

  def take_item(%Mail{item_guid: item_guid} = mail) when item_guid > 0 do
    {:ok, item_guid, mail.cod, %{mail | item_guid: 0, cod: 0}}
  end

  def take_item(%Mail{}), do: {:error, :no_item}

  def deletable?(%Mail{cod: 0}), do: true
  def deletable?(%Mail{}), do: false

  def return_attrs(%Mail{sender_type: :normal, sender: sender} = mail, receiver, now)
      when is_integer(sender) and sender > 0 do
    {:ok,
     %{
       sender: receiver,
       sender_type: :normal,
       receiver: sender,
       subject: mail.subject,
       body: mail.body,
       stationery: mail.stationery,
       item_guid: mail.item_guid,
       money: mail.money,
       checked: @checked_returned,
       deliver_at: now
     }}
  end

  def return_attrs(%Mail{}, _receiver, _now), do: {:error, :not_returnable}

  def item_text_id(%Mail{id: id, body: body}) when body != "", do: id
  def item_text_id(%Mail{}), do: 0

  defp delivery_delay(%Mail{item_guid: item_guid, money: money}) when item_guid > 0 or money > 0, do: @delivery_delay_ms

  defp delivery_delay(%Mail{}), do: 0

  defp expiration(%Mail{cod: cod}) when cod > 0, do: @cod_expiration_ms
  defp expiration(%Mail{}), do: @expiration_ms

  defp validate!(%Mail{} = mail) do
    if valid_identity?(mail) and valid_text?(mail) and valid_contents?(mail),
      do: :ok,
      else: raise(ArgumentError, "invalid mail")
  end

  defp valid_identity?(%Mail{} = mail) do
    is_integer(mail.id) and mail.id > 0 and is_integer(mail.receiver) and mail.receiver > 0 and
      is_integer(mail.sender) and mail.sender_type in [:normal, :auction, :creature, :game_object, :item]
  end

  defp valid_text?(%Mail{} = mail), do: is_binary(mail.subject) and is_binary(mail.body)

  defp valid_contents?(%Mail{} = mail) do
    is_integer(mail.item_guid) and mail.item_guid >= 0 and is_integer(mail.money) and mail.money >= 0 and
      is_integer(mail.cod) and mail.cod >= 0
  end
end
