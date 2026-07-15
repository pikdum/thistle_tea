defmodule ThistleTea.Game.Player.MailTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Mail
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Mail, as: MailLoader
  alias ThistleTea.Game.World.PostOffice

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
