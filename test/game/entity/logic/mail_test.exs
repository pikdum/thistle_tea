defmodule ThistleTea.Game.Entity.Logic.MailTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mail
  alias ThistleTea.Game.Entity.Logic.Mail, as: MailLogic

  @now 1_000_000

  describe "new/2" do
    test "delivers letters immediately" do
      mail = MailLogic.new(%{id: 1, sender: 10, receiver: 20, body: "hello"}, @now)

      assert mail.deliver_at == @now
      assert MailLogic.visible?(mail, @now)
      assert MailLogic.item_text_id(mail) == 1
    end

    test "delays item and money mail by one hour" do
      item_mail = MailLogic.new(%{id: 1, sender: 10, receiver: 20, item_guid: 30}, @now)
      money_mail = MailLogic.new(%{id: 2, sender: 10, receiver: 20, money: 100}, @now)

      assert item_mail.deliver_at == @now + MailLogic.delivery_delay_ms()
      assert money_mail.deliver_at == item_mail.deliver_at
      refute MailLogic.visible?(item_mail, @now)
    end

    test "expires COD mail after three days" do
      mail = MailLogic.new(%{id: 1, sender: 10, receiver: 20, item_guid: 30, cod: 50}, @now)

      assert mail.expire_at == mail.deliver_at + to_timeout(day: 3)
    end
  end

  describe "mailbox transitions" do
    test "merges retries idempotently" do
      original = mail(1)
      replacement = %{original | subject: "new"}

      assert [%Mail{subject: "new"}] = MailLogic.merge([original], [replacement])
    end

    test "marking mail read shortens its remaining lifetime" do
      original = mail(1)
      read = MailLogic.mark_read(original, @now)

      assert (read.checked &&& 1) == 1
      assert read.expire_at < original.expire_at
      refute MailLogic.unread?(read, @now)
    end

    test "taking contents leaves the envelope" do
      original = %{mail(1) | item_guid: 44, money: 75, cod: 20}

      assert {:ok, 75, without_money} = MailLogic.take_money(original)
      assert without_money.money == 0

      assert {:ok, 44, 20, empty} = MailLogic.take_item(without_money)
      assert empty.item_guid == 0
      assert empty.cod == 0
      assert MailLogic.deletable?(empty)
    end

    test "builds a return addressed to the original player" do
      original = %{mail(1) | sender: 50, receiver: 60, item_guid: 70, cod: 99}

      assert {:ok, attrs} = MailLogic.return_attrs(original, 60, @now)
      assert attrs.sender == 60
      assert attrs.receiver == 50
      assert attrs.item_guid == 70
      refute Map.has_key?(attrs, :cod)
    end
  end

  defp mail(id) do
    MailLogic.new(
      %{id: id, sender: 10, receiver: 20, deliver_at: @now, expire_at: @now + to_timeout(day: 30)},
      @now
    )
  end
end
