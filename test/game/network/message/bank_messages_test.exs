defmodule ThistleTea.Game.Network.Message.BankMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgAutobankItem
  alias ThistleTea.Game.Network.Message.CmsgAutostoreBankItem
  alias ThistleTea.Game.Network.Message.CmsgBankerActivate
  alias ThistleTea.Game.Network.Message.CmsgBuyBankSlot
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgBuyBankSlotResult
  alias ThistleTea.Game.Network.Message.SmsgShowBank
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "client codecs" do
    test "decodes banker activation" do
      guid = 0xF130_001122_334455
      payload = <<guid::little-size(64)>>

      assert CmsgBankerActivate.from_binary(payload) == %CmsgBankerActivate{banker_guid: guid}

      assert Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_BANKER_ACTIVATE), payload: payload}) ==
               %CmsgBankerActivate{banker_guid: guid}
    end

    test "decodes bank slot purchases" do
      guid = 0xF130_001122_334455
      payload = <<guid::little-size(64)>>

      assert CmsgBuyBankSlot.from_binary(payload) == %CmsgBuyBankSlot{banker_guid: guid}

      assert Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_BUY_BANK_SLOT), payload: payload}) ==
               %CmsgBuyBankSlot{banker_guid: guid}
    end

    test "decodes automatic bank transfers" do
      assert CmsgAutobankItem.from_binary(<<255, 23>>) == %CmsgAutobankItem{source_bag: 255, source_slot: 23}

      assert CmsgAutostoreBankItem.from_binary(<<255, 39>>) ==
               %CmsgAutostoreBankItem{source_bag: 255, source_slot: 39}

      assert Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_AUTOBANK_ITEM), payload: <<255, 23>>}) ==
               %CmsgAutobankItem{source_bag: 255, source_slot: 23}

      assert Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_AUTOSTORE_BANK_ITEM), payload: <<255, 39>>}) ==
               %CmsgAutostoreBankItem{
                 source_bag: 255,
                 source_slot: 39
               }
    end

    test "rejects malformed payloads" do
      assert_raise FunctionClauseError, fn -> CmsgBankerActivate.from_binary(<<1>>) end
      assert_raise FunctionClauseError, fn -> CmsgBuyBankSlot.from_binary(<<1>>) end
      assert_raise FunctionClauseError, fn -> CmsgAutobankItem.from_binary(<<1>>) end
      assert_raise FunctionClauseError, fn -> CmsgAutostoreBankItem.from_binary(<<1>>) end
    end
  end

  describe "server codecs" do
    test "encodes show bank" do
      guid = 0xF130_001122_334455
      assert SmsgShowBank.to_binary(%SmsgShowBank{banker_guid: guid}) == <<guid::little-size(64)>>
    end

    test "encodes bank slot results" do
      for result <- 0..2 do
        assert SmsgBuyBankSlotResult.to_binary(%SmsgBuyBankSlotResult{result: result}) ==
                 <<result::little-size(32)>>
      end
    end
  end
end
