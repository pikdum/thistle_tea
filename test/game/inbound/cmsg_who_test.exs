defmodule ThistleTea.Game.Inbound.CmsgWhoTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Who.Query
  alias ThistleTea.Game.Inbound.CmsgWho
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  defp message(payload), do: Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_WHO), payload: payload})

  describe "from_binary/1" do
    test "reads the level range, name and guild filters, masks, zones, and search terms" do
      payload =
        <<10::little-32, 60::little-32, "ced", 0, "", 0, 0xFFFF::little-32, 0x100::little-32, 2::little-32,
          1_519::little-32, 12::little-32, 2::little-32, "storm", 0, "light", 0>>

      assert %CmsgWho{
               query: %Query{
                 level_min: 10,
                 level_max: 60,
                 name: "ced",
                 guild: "",
                 race_mask: 0xFFFF,
                 class_mask: 0x100,
                 zones: [1_519, 12],
                 terms: ["storm", "light"]
               }
             } = message(payload)
    end

    test "turns away more zones or search terms than the client can send" do
      zones = <<0::little-32, 60::little-32, 0, 0, 0::little-32, 0::little-32, 11::little-32>>
      assert %CmsgWho{query: nil} = message(zones <> :binary.copy(<<1::little-32>>, 11) <> <<0::little-32>>)

      terms = <<0::little-32, 60::little-32, 0, 0, 0::little-32, 0::little-32, 0::little-32, 5::little-32>>
      assert %CmsgWho{query: nil} = message(terms <> :binary.copy(<<"a", 0>>, 5))
    end
  end
end
