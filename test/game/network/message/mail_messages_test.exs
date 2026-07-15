defmodule ThistleTea.Game.Network.Message.MailMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mail
  alias ThistleTea.Game.Network.Message.CmsgSendMail
  alias ThistleTea.Game.Network.Message.MsgQueryNextMailTime
  alias ThistleTea.Game.Network.Message.SmsgMailListResult
  alias ThistleTea.Game.Network.Message.SmsgSendMailResult

  describe "CMSG_SEND_MAIL" do
    test "decodes a Vanilla single-attachment request" do
      payload =
        <<50::little-size(64)>> <>
          "Receiver\0Subject\0Body\0" <>
          <<41::little-size(32), 0::little-size(32), 60::little-size(64), 70::little-size(32), 80::little-size(32),
            0::little-size(64)>>

      assert %CmsgSendMail{
               mailbox: 50,
               receiver: "Receiver",
               subject: "Subject",
               body: "Body",
               stationery: 41,
               item_guid: 60,
               money: 70,
               cod: 80
             } = CmsgSendMail.from_binary(payload)
    end
  end

  describe "SMSG_SEND_MAIL_RESULT" do
    test "encodes item-taken details" do
      message = %SmsgSendMailResult{mail_id: 1, action: 2, result: 0, item_entry: 3, item_count: 4}

      assert SmsgSendMailResult.to_binary(message) ==
               <<1::little-size(32), 2::little-size(32), 0::little-size(32), 3::little-size(32), 4::little-size(32)>>
    end
  end

  describe "SMSG_MAIL_LIST_RESULT" do
    test "encodes normal sender and attachment fields" do
      mail = %Mail{
        id: 1,
        sender: 2,
        receiver: 3,
        subject: "Hi",
        deliver_at: 1_000,
        expire_at: 1_000 + to_timeout(day: 1),
        item_guid: 4,
        money: 5,
        cod: 6
      }

      item = Item.build(%ItemTemplate{entry: 7, stackable: 20, max_durability: 10}, 4, stack_count: 2)
      binary = SmsgMailListResult.to_binary(%SmsgMailListResult{mails: [{mail, item}], now: 1_000})

      assert <<1, 1::little-size(32), 0, 2::little-size(64), "Hi\0", _rest::binary>> = binary
      assert byte_size(binary) == 78
    end
  end

  describe "MSG_QUERY_NEXT_MAIL_TIME" do
    test "encodes the Vanilla unread marker" do
      assert MsgQueryNextMailTime.to_binary(%MsgQueryNextMailTime{unread_mails: 0.0}) ==
               <<0.0::little-float-size(32)>>
    end
  end
end
