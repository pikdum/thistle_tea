defmodule ThistleTea.Game.Network.Message.PetitionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guild.Member
  alias ThistleTea.Game.Guild.Petitions.Petition
  alias ThistleTea.Game.Guild.Petitions.Signature
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes

  describe "from_binary/1" do
    test "registers and parses the Vanilla petition requests" do
      opcodes = [
        :CMSG_PETITION_SHOWLIST,
        :CMSG_PETITION_BUY,
        :CMSG_PETITION_SHOW_SIGNATURES,
        :CMSG_PETITION_QUERY,
        :CMSG_OFFER_PETITION,
        :CMSG_PETITION_SIGN,
        :CMSG_TURN_IN_PETITION,
        :MSG_PETITION_DECLINE,
        :MSG_PETITION_RENAME
      ]

      assert Enum.all?(opcodes, &(Opcodes.get(&1) |> Dispatch.implemented?()))

      assert %Message.CmsgPetitionShowlist{npc_guid: 10} =
               Message.CmsgPetitionShowlist.from_binary(<<10::little-size(64)>>)

      buy = <<10::little-size(64), 0::little-size(32), 0::little-size(64)>> <> "Fellowship" <> <<0::size(384)>>
      assert %Message.CmsgPetitionBuy{npc_guid: 10, name: "Fellowship"} = Message.CmsgPetitionBuy.from_binary(buy)

      assert %Message.CmsgPetitionQuery{petition_id: 4, item_guid: 50} =
               Message.CmsgPetitionQuery.from_binary(<<4::little-size(32), 50::little-size(64)>>)

      assert %Message.CmsgOfferPetition{item_guid: 50, target_guid: 2} =
               Message.CmsgOfferPetition.from_binary(<<50::little-size(64), 2::little-size(64)>>)

      assert %Message.CmsgPetitionSign{item_guid: 50} = Message.CmsgPetitionSign.from_binary(<<50::little-size(64), 0>>)

      assert %Message.MsgPetitionRenameClient{item_guid: 50, name: "New Name"} =
               Message.MsgPetitionRenameClient.from_binary(<<50::little-size(64)>> <> "New Name" <> <<0>>)
    end
  end

  describe "to_binary/1" do
    test "encodes charter vendor, query, signatures, and results" do
      owner = %Member{guid: 1, name: "Founder", race: 1, class: 1, level: 20}
      signer = %Member{guid: 2, name: "Signer", race: 1, class: 1, level: 20}

      petition = %Petition{
        id: 5,
        item_guid: 50,
        owner: owner,
        owner_account_id: 100,
        name: "Fellowship",
        signatures: %{2 => %Signature{member: signer, account_id: 101}}
      }

      assert Message.SmsgPetitionShowlist.to_binary(%Message.SmsgPetitionShowlist{npc_guid: 10}) ==
               <<10::little-size(64), 1, 1::little-size(32), 5863::little-size(32), 16_161::little-size(32),
                 1000::little-size(32), 1::little-size(32)>>

      assert Message.SmsgPetitionShowSignatures.to_binary(%Message.SmsgPetitionShowSignatures{petition: petition}) ==
               <<50::little-size(64), 1::little-size(64), 5::little-size(32), 1, 2::little-size(64),
                 0::little-size(32)>>

      query = Message.SmsgPetitionQueryResponse.to_binary(%Message.SmsgPetitionQueryResponse{petition: petition})

      assert <<5::little-size(32), 1::little-size(64), "Fellowship", 0, 0, 1::little-size(32), 9::little-size(32),
               9::little-size(32), _rest::binary>> = query

      assert Message.SmsgPetitionSignResults.to_binary(%Message.SmsgPetitionSignResults{
               item_guid: 50,
               signer_guid: 2,
               result: :ok
             }) == <<50::little-size(64), 2::little-size(64), 0::little-size(32)>>

      assert Message.SmsgTurnInPetitionResults.to_binary(%Message.SmsgTurnInPetitionResults{result: :need_more}) ==
               <<4::little-size(32)>>
    end
  end
end
