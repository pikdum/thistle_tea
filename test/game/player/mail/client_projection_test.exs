defmodule ThistleTea.Game.Player.Mail.ClientProjectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgSendMailResult
  alias ThistleTea.Game.Player.Mail.ClientProjection

  describe "result/4" do
    test "maps semantic outcomes to protocol fields" do
      ClientProjection.result(42, :item_taken, :equip_error,
        equip_error: 12,
        item_entry: 99,
        item_count: 3
      )

      assert_receive {
        :"$gen_cast",
        {:send_packet,
         %SmsgSendMailResult{
           mail_id: 42,
           action: 2,
           result: 1,
           equip_error: 12,
           item_entry: 99,
           item_count: 3
         }}
      }
    end
  end
end
