defmodule ThistleTea.Game.Player.Mail do
  @moduledoc """
  Player-mail boundary: validates mailbox interactions, coordinates item and
  coin transfers, and translates pure mailbox transitions into packets and
  Post Office operations.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Mail, as: DataMail
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Mail, as: MailLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Mail, as: MailLoader
  alias ThistleTea.Game.World.PostOffice

  @mailbox_type 19
  @interaction_distance 5.0
  @body_item_entry 8383
  @max_coinage 0x7FFFFFFE

  @action_send 0
  @action_money_taken 1
  @action_item_taken 2
  @action_returned 3
  @action_deleted 4
  @action_made_permanent 5

  @result_ok 0
  @result_equip_error 1
  @result_self 2
  @result_not_enough_money 3
  @result_recipient_not_found 4
  @result_not_same_team 5
  @result_internal 6
  @result_attachment_invalid 19

  def open_session(%Character{internal: internal} = character, guid) when is_integer(guid) do
    {token, pending} = PostOffice.open(guid)
    mailbox = MailLogic.merge(internal.mailbox, pending)
    PostOffice.acknowledge(guid, token, Enum.map(pending, & &1.id))
    {%{character | internal: %{internal | mailbox: mailbox}}, token}
  end

  def send_quest_reward(state, _sender_guid, %Quest{reward_mail_template_id: 0}), do: state

  def send_quest_reward(%{guid: receiver} = state, sender_guid, %Quest{} = quest) do
    case MailLoader.get(quest.reward_mail_template_id) do
      %{body: body, attachment: attachment} ->
        item = create_quest_mail_item(attachment, receiver)

        attrs = %{
          sender: Guid.entry(sender_guid),
          sender_type: quest_sender_type(sender_guid),
          receiver: receiver,
          body: body,
          template_id: quest.reward_mail_template_id,
          item_guid: if(item, do: item.object.guid, else: 0),
          money: quest.reward_mail_money,
          deliver_at: Time.now() + quest.reward_mail_delay_secs * 1_000
        }

        case PostOffice.post(attrs) do
          {:ok, _mail} ->
            state

          {:error, _reason} ->
            delete_item(item)
            state
        end

      nil ->
        state
    end
  end

  def schedule_delivery(%{character: %Character{internal: %{mailbox: mailbox}}} = state) do
    if is_reference(state.mail_delivery_ref), do: Process.cancel_timer(state.mail_delivery_ref)

    case MailLogic.next_delivery(mailbox, Time.now()) do
      nil ->
        %{state | mail_delivery_ref: nil}

      deliver_at ->
        %{
          state
          | mail_delivery_ref:
              Process.send_after(self(), {:mail_delivery_ready, deliver_at}, max(deliver_at - Time.now(), 0))
        }
    end
  end

  def receive_delivery(
        %{guid: guid, mail_session_token: token, character: %Character{internal: internal} = character} = state,
        token,
        %DataMail{} = mail
      ) do
    mailbox = MailLogic.add(internal.mailbox, mail)
    PostOffice.acknowledge(guid, token, [mail.id])
    state = %{state | character: %{character | internal: %{internal | mailbox: mailbox}}}
    if MailLogic.visible?(mail, Time.now()), do: Network.send_packet(%Message.SmsgReceivedMail{})
    schedule_delivery(state)
  end

  def receive_delivery(state, _token, %DataMail{}), do: state

  def delivery_ready(%{character: %Character{internal: %{mailbox: mailbox}}} = state, deliver_at) do
    now = Time.now()

    if Enum.any?(mailbox, &(&1.deliver_at == deliver_at and MailLogic.unread?(&1, now))) do
      Network.send_packet(%Message.SmsgReceivedMail{})
    end

    schedule_delivery(%{state | mail_delivery_ref: nil})
  end

  def send_mail(%{ready: true, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %Character{} = recipient <- CharacterStore.get_by_name(message.receiver),
         :ok <- validate_recipient(character, recipient),
         :ok <- validate_content(message),
         :ok <- validate_cod(message),
         {:ok, inventory_result, item} <- detach_item(character, message.item_guid),
         :ok <- validate_item(item),
         cost = MailLogic.postage() + message.money,
         true <- character.player.coinage >= cost do
      transfer_sent_item(item, recipient.object.guid)

      case PostOffice.post(mail_attrs(character, recipient, message, item)) do
        {:ok, _mail} ->
          player = %{inventory_result.player | coinage: character.player.coinage - cost}
          state = InventoryUpdate.apply(state, {:ok, %{inventory_result | player: player}})
          send_result(0, @action_send, @result_ok)
          state

        {:error, _reason} ->
          restore_sent_item(item)
          send_error(state, @result_internal)
      end
    else
      nil -> send_error(state, @result_recipient_not_found)
      {:error, :self} -> send_error(state, @result_self)
      {:error, :team} -> send_error(state, @result_not_same_team)
      {:error, :cod_without_item} -> send_error(state, @result_attachment_invalid)
      {:error, :invalid_item} -> send_error(state, @result_attachment_invalid)
      {:error, _error, _item1, _item2} -> send_error(state, @result_attachment_invalid)
      false -> send_error(state, @result_not_enough_money)
      {:error, _reason} -> send_error(state, @result_internal)
    end
  end

  def send_mail(state, _message), do: state

  def list(%{ready: true, character: %Character{internal: %{mailbox: mailbox}} = character} = state, mailbox_guid) do
    if validate_mailbox(character, mailbox_guid) == :ok do
      now = Time.now()

      mails =
        mailbox
        |> MailLogic.visible(now)
        |> Enum.map(fn mail -> {mail, ItemStore.get(mail.item_guid)} end)

      Network.send_packet(%Message.SmsgMailListResult{mails: mails, now: now})
    end

    state
  end

  def list(state, _mailbox_guid), do: state

  def take_money(%{ready: true, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %DataMail{} = mail <- visible_mail(character, message.mail_id),
         {:ok, money, mail} <- MailLogic.take_money(mail),
         true <- character.player.coinage <= @max_coinage - money do
      player = %{character.player | coinage: character.player.coinage + money}
      state = put_mail(state, mail)
      state = InventoryUpdate.apply(state, {:ok, player})
      send_result(mail.id, @action_money_taken, @result_ok)
      state
    else
      false ->
        send_result(message.mail_id, @action_money_taken, @result_internal)
        state

      _ ->
        state
    end
  end

  def take_money(state, _message), do: state

  def take_item(%{ready: true, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %DataMail{} = mail <- visible_mail(character, message.mail_id),
         {:ok, item_guid, cod, updated_mail} <- MailLogic.take_item(mail),
         %Item{} = item <- ItemStore.get(item_guid),
         true <- character.player.coinage >= cod,
         {:ok, result, placement} <- Inventory.store(character.player, state.guid, item, &ItemStore.get/1) do
      player = %{result.player | coinage: character.player.coinage - cod}
      state = put_mail(state, updated_mail)
      finish_item_placement(item, placement)
      state = InventoryUpdate.apply(state, {:ok, %{result | player: player}})
      pay_cod(mail, state.guid, cod)

      send_result(mail.id, @action_item_taken, @result_ok,
        item_entry: item.object.entry,
        item_count: item.item.stack_count || 1
      )

      state
    else
      false ->
        send_result(message.mail_id, @action_item_taken, @result_not_enough_money)
        state

      {:error, error} ->
        send_item_inventory_error(state, message.mail_id, error)

      _ ->
        state
    end
  end

  def take_item(state, _message), do: state

  def mark_read(%{ready: true, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %DataMail{} = mail <- visible_mail(character, message.mail_id) do
      put_mail(state, MailLogic.mark_read(mail, Time.now()))
    else
      _ -> state
    end
  end

  def mark_read(state, _message), do: state

  def return_to_sender(%{ready: true, guid: guid, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %DataMail{} = mail <- visible_mail(character, message.mail_id),
         {:ok, attrs} <- MailLogic.return_attrs(mail, guid, Time.now()) do
      attrs = apply_return_delay(attrs, character, mail)
      transfer_returned_item(mail)

      case PostOffice.post(attrs) do
        {:ok, _returned} ->
          state = remove_mail(state, mail.id)
          send_result(mail.id, @action_returned, @result_ok)
          state

        {:error, _reason} ->
          transfer_item_owner(mail.item_guid, guid)
          state
      end
    else
      _ -> state
    end
  end

  def return_to_sender(state, _message), do: state

  def delete(%{ready: true, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %DataMail{} = mail <- visible_mail(character, message.mail_id),
         true <- MailLogic.deletable?(mail) do
      if mail.item_guid > 0, do: ItemStore.delete(mail.item_guid)
      state = remove_mail(state, mail.id)
      send_result(mail.id, @action_deleted, @result_ok)
      state
    else
      _ -> state
    end
  end

  def delete(state, _message), do: state

  def query_text(%{character: %Character{} = character} = state, message) do
    mail = MailLogic.find(character.internal.mailbox, message.mail_id)

    text =
      case mail do
        %DataMail{id: id, body: body} when id == message.item_text_id -> body
        _ -> ""
      end

    Network.send_packet(%Message.SmsgItemTextQueryResponse{item_text_id: message.item_text_id, text: text})
    state
  end

  def query_text(state, _message), do: state

  def create_text_item(%{ready: true, character: %Character{} = character} = state, message) do
    with :ok <- validate_mailbox(character, message.mailbox),
         %DataMail{body: body} = mail when body != "" <- visible_mail(character, message.mail_id) do
      store_text_item(state, mail)
    else
      _ -> state
    end
  end

  def create_text_item(state, _message), do: state

  def query_next_time(%{character: %Character{internal: %{mailbox: mailbox}}} = state) do
    unread_mails = if MailLogic.has_unread?(mailbox, Time.now()), do: 0.0, else: -1.0
    Network.send_packet(%Message.MsgQueryNextMailTime{unread_mails: unread_mails})
    state
  end

  def query_next_time(state), do: state

  defp validate_mailbox(%Character{} = character, mailbox_guid) do
    with :game_object <- Guid.entity_type(mailbox_guid),
         %GameObjectTemplate{type: @mailbox_type} <- GameObjectTemplateLoader.get(Guid.entry(mailbox_guid)),
         distance when is_number(distance) and distance <= @interaction_distance <-
           World.distance_to_guid(character, mailbox_guid) do
      :ok
    else
      _ -> {:error, :invalid_mailbox}
    end
  end

  defp create_quest_mail_item(nil, _receiver), do: nil

  defp create_quest_mail_item(%{item: entry, min_count: min_count, max_count: max_count}, receiver) do
    count = min_count + :rand.uniform(max(max_count - min_count + 1, 1)) - 1
    ItemStore.create(entry, owner: receiver, stack_count: count)
  end

  defp quest_sender_type(sender_guid) do
    if Guid.entity_type(sender_guid) == :game_object, do: :game_object, else: :creature
  end

  defp delete_item(%Item{} = item), do: ItemStore.delete(item.object.guid)
  defp delete_item(nil), do: :ok

  defp validate_recipient(%Character{} = sender, %Character{} = recipient) do
    cond do
      sender.object.guid == recipient.object.guid -> {:error, :self}
      not Party.same_team?(sender.unit.race, recipient.unit.race) -> {:error, :team}
      true -> :ok
    end
  end

  defp validate_cod(%{cod: cod, item_guid: 0}) when cod > 0, do: {:error, :cod_without_item}
  defp validate_cod(_message), do: :ok

  defp validate_content(%{subject: subject, body: body, cod: cod}) do
    if byte_size(subject) <= 64 and byte_size(body) <= 500 and cod <= 100_000_000,
      do: :ok,
      else: {:error, :invalid_content}
  end

  defp detach_item(%Character{} = character, 0) do
    {:ok, %{player: character.player, items: [], destroyed: []}, nil}
  end

  defp detach_item(%Character{} = character, item_guid) do
    with %Item{} <- ItemStore.get(item_guid),
         pos when not is_nil(pos) <- Inventory.find_position(character.player, item_guid, &ItemStore.get/1) do
      Inventory.detach(character.player, pos, &ItemStore.get/1)
    else
      _ -> {:error, :invalid_item}
    end
  end

  defp validate_item(nil), do: :ok

  defp validate_item(%Item{item: %{duration: duration}}) when is_integer(duration) and duration > 0,
    do: {:error, :invalid_item}

  defp validate_item(%Item{} = item) do
    if Bitwise.band(Item.template(item).flags || 0, 0x02) == 0, do: :ok, else: {:error, :invalid_item}
  end

  defp mail_attrs(character, recipient, message, item) do
    %{
      sender: character.object.guid,
      receiver: recipient.object.guid,
      sender_type: :normal,
      subject: message.subject,
      body: message.body,
      stationery: 41,
      item_guid: if(item, do: item.object.guid, else: 0),
      money: message.money,
      cod: message.cod,
      checked: if(message.body == "", do: MailLogic.checked_copied(), else: 0)
    }
  end

  defp transfer_sent_item(nil, _recipient), do: :ok

  defp transfer_sent_item(%Item{} = item, recipient) do
    ItemStore.put(%{item | item: %{item.item | owner: recipient, contained: recipient}})
  end

  defp restore_sent_item(nil), do: :ok
  defp restore_sent_item(%Item{} = item), do: ItemStore.put(item)

  defp transfer_returned_item(%DataMail{item_guid: item_guid, sender: sender}) when item_guid > 0 do
    transfer_item_owner(item_guid, sender)
  end

  defp transfer_returned_item(%DataMail{}), do: :ok

  defp transfer_item_owner(item_guid, owner) when is_integer(item_guid) and item_guid > 0 do
    case ItemStore.get(item_guid) do
      %Item{} = item -> ItemStore.put(%{item | item: %{item.item | owner: owner, contained: owner}})
      nil -> :ok
    end
  end

  defp transfer_item_owner(_item_guid, _owner), do: :ok

  defp apply_return_delay(attrs, %Character{} = receiver, %DataMail{sender: sender, item_guid: item_guid})
       when item_guid > 0 do
    case CharacterStore.get(Guid.low_guid(sender)) do
      %Character{account_id: account_id} when account_id == receiver.account_id -> attrs
      %Character{} -> %{attrs | deliver_at: Time.now() + MailLogic.delivery_delay_ms()}
      nil -> attrs
    end
  end

  defp apply_return_delay(attrs, %Character{}, %DataMail{}), do: attrs

  defp visible_mail(%Character{internal: %{mailbox: mailbox}}, id) do
    case MailLogic.find(mailbox, id) do
      %DataMail{} = mail -> if MailLogic.visible?(mail, Time.now()), do: mail
      nil -> nil
    end
  end

  defp put_mail(%{character: %Character{internal: internal} = character} = state, %DataMail{} = mail) do
    mailbox = MailLogic.replace(internal.mailbox, mail)
    %{state | character: %{character | internal: %{internal | mailbox: mailbox}}}
  end

  defp remove_mail(%{character: %Character{internal: internal} = character} = state, id) do
    mailbox = MailLogic.remove(internal.mailbox, id)
    %{state | character: %{character | internal: %{internal | mailbox: mailbox}}}
  end

  defp finish_item_placement(_item, {:placed, _position, %Item{} = placed}) do
    ItemStore.put(placed)
    Network.send_packet(UpdateObject.from_item(placed))
  end

  defp finish_item_placement(%Item{} = item, :merged), do: ItemStore.delete(item.object.guid)

  defp store_text_item(state, %DataMail{} = mail) do
    case ItemStore.create(@body_item_entry, owner: state.guid) do
      %Item{} = item -> store_created_text_item(state, mail, item)
      nil -> state
    end
  end

  defp store_created_text_item(state, %DataMail{} = mail, %Item{} = item) do
    item = %{item | item: %{item.item | item_text_id: mail.id}}

    case Inventory.store(state.character.player, state.guid, item, &ItemStore.get/1) do
      {:ok, result, placement} ->
        finish_item_placement(item, placement)
        state = InventoryUpdate.apply(state, {:ok, result})
        mail = %{mail | checked: Bitwise.bor(mail.checked, MailLogic.checked_copied())}
        state = put_mail(state, mail)
        send_result(mail.id, @action_made_permanent, @result_ok)
        state

      {:error, error} ->
        ItemStore.delete(item.object.guid)
        send_item_inventory_error(state, mail.id, error)
    end
  end

  defp pay_cod(_mail, _buyer, 0), do: :ok

  defp pay_cod(%DataMail{sender_type: :normal, sender: sender, subject: subject}, buyer, cod) do
    PostOffice.post(%{
      sender: buyer,
      receiver: sender,
      sender_type: :normal,
      subject: subject,
      money: cod,
      checked: MailLogic.checked_cod_payment(),
      deliver_at: Time.now()
    })
  end

  defp pay_cod(%DataMail{}, _buyer, _cod), do: :ok

  defp send_error(state, result) do
    send_result(0, @action_send, result)
    state
  end

  defp send_item_inventory_error(state, mail_id, error) do
    send_result(mail_id, @action_item_taken, @result_equip_error, equip_error: Inventory.error_code(error))

    state
  end

  defp send_result(mail_id, action, result, opts \\ []) do
    Network.send_packet(%Message.SmsgSendMailResult{
      mail_id: mail_id,
      action: action,
      result: result,
      equip_error: Keyword.get(opts, :equip_error, 0),
      item_entry: Keyword.get(opts, :item_entry, 0),
      item_count: Keyword.get(opts, :item_count, 0)
    })
  end
end
