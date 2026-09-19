defmodule ThistleTea.Game.Player.MailTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgSendMail
  alias ThistleTea.Game.Network.Message.SmsgSendMailResult
  alias ThistleTea.Game.Player.Mail
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Mail, as: MailLoader
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.WorldRef

  describe "send_mail/2" do
    test "rejects a bound attachment without moving it or charging postage" do
      id = System.unique_integer([:positive, :monotonic]) + 1_000_000

      recipient = %Character{
        id: id,
        object: %Object{guid: id},
        unit: %Unit{race: 1},
        internal: %Internal{name: "BoundMail#{id}"}
      }

      CharacterStore.put(recipient)
      sender = id + 1
      mailbox_guid = Guid.from_low_guid(:game_object, id, id)
      :ets.insert(GameObjectTemplateLoader, {id, %GameObjectTemplate{entry: id, type: 19}})

      mailbox = %{
        object: %Object{guid: mailbox_guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      Position.put(mailbox, :game_objects)
      item = ItemStore.create(%ItemTemplate{entry: id, inventory_type: 5, bonding: 2}, owner: sender)
      item = item |> Item.bind_on_equip() |> ItemStore.put()

      character = %Character{
        object: %Object{guid: sender},
        unit: %Unit{race: 1},
        player: %Player{coinage: 100, inv1: item.object.guid},
        internal: mailbox.internal,
        movement_block: mailbox.movement_block
      }

      state = %{ready: true, guid: sender, character: character}

      message = %CmsgSendMail{
        mailbox: mailbox_guid,
        receiver: recipient.internal.name,
        subject: "Bound",
        body: "",
        item_guid: item.object.guid
      }

      on_exit(fn ->
        ItemStore.delete(item.object.guid)
        :ets.delete(CharacterStore, id)
        :ets.delete(GameObjectTemplateLoader, id)
        Position.remove(mailbox, :game_objects)
      end)

      assert Mail.send_mail(state, message) == state
      assert ItemStore.get(item.object.guid) == item
      assert_receive {:"$gen_cast", {:send_packet, %SmsgSendMailResult{action: 0, result: 19}}}
    end
  end

  describe "send_quest_reward/3" do
    test "posts cached quest text and its template attachment" do
      unique = System.unique_integer([:positive, :monotonic])
      receiver = Guid.from_low_guid(:player, unique)
      sender = Guid.from_low_guid(:mob, 123, unique)
      template_id = 100_000 + unique
      item_entry = 200_000 + unique
      item_template = %ItemTemplate{entry: item_entry, stackable: 20}

      :ets.insert(ItemLoader, {item_entry, item_template})

      :ets.insert(
        MailLoader,
        {template_id, %{body: "A quest letter", attachment: %{item: item_entry, min_count: 2, max_count: 2}}}
      )

      {token, []} = PostOffice.open(receiver)

      quest = %Quest{
        reward_mail_template_id: template_id,
        reward_mail_delay_secs: 60,
        reward_mail_money: 25
      }

      assert %{guid: ^receiver} = Mail.send_quest_reward(%{guid: receiver}, sender, quest)
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, mail}}

      assert mail.sender_type == :creature
      assert mail.sender == 123
      assert mail.receiver == receiver
      assert mail.body == "A quest letter"
      assert mail.template_id == template_id
      assert mail.money == 25
      assert mail.deliver_at > System.monotonic_time(:millisecond)

      item = ItemStore.get(mail.item_guid)
      assert item.object.entry == item_entry
      assert item.item.stack_count == 2
      assert item.item.owner == receiver

      PostOffice.acknowledge(receiver, token, [mail.id])
      assert :ok = PostOffice.close(receiver, token, [])

      ItemStore.delete(mail.item_guid)
      :ets.delete(ItemLoader, item_entry)
      :ets.delete(MailLoader, template_id)
    end
  end
end
