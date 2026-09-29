defmodule ThistleTea.Game.World.Entity.Player.GroupsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Groups
  alias ThistleTea.Game.World.Entity.Registry
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  setup [:party]

  describe "random_roll/3" do
    test "shares one server result from any member across the whole raid", %{leader: leader, member: member} do
      outsider = unique_guid()
      Registry.register(outsider)
      offline = unique_guid()
      :ok = PartySystem.invite(leader.guid, "First", offline)
      {:ok, _} = PartySystem.accept(offline, "Offline")
      on_exit(fn -> PartySystem.leave(offline) end)
      {:ok, _} = PartySystem.convert_raid(leader.guid)
      {:ok, group} = PartySystem.change_subgroup(leader.guid, member.guid, 7)

      member = %{
        member
        | character: %{member.character | internal: %{member.character.internal | world: WorldRef.open(1)}}
      }

      assert Groups.random_roll(member, 37, 91) == member
      guid = member.guid

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.MsgRandomRollResponse{guid: ^guid, minimum: 37, maximum: 91} = roll}}

      assert roll.result in 37..91
      assert_receive {:"$gen_cast", {:send_packet, ^roll}}
      refute_received {:"$gen_cast", {:send_packet, %Message.MsgRandomRollResponse{}}}
      assert PartySystem.group_of(guid) == group
    end

    test "uses current membership after leaving and returns solo rolls only once", %{leader: leader, member: member} do
      PartySystem.leave(member.guid)

      for state <- [leader, member], bound <- [0, 1_000_000] do
        assert Groups.random_roll(state, bound, bound) == state
        guid = state.guid

        assert_receive {:"$gen_cast",
                        {:send_packet,
                         %Message.MsgRandomRollResponse{guid: ^guid, result: ^bound, minimum: ^bound, maximum: ^bound}}}

        refute_received {:"$gen_cast", {:send_packet, %Message.MsgRandomRollResponse{}}}
      end
    end

    test "accepts the complete range and shares the same result with the party", %{leader: leader} do
      assert Groups.random_roll(leader, 0, 1_000_000) == leader
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRandomRollResponse{} = roll}}
      assert roll.result in 0..1_000_000
      assert_receive {:"$gen_cast", {:send_packet, ^roll}}
      refute_received {:"$gen_cast", {:send_packet, %Message.MsgRandomRollResponse{}}}
    end

    test "rejects reversed, negative, oversized and noninteger bounds", %{leader: leader} do
      for {minimum, maximum} <- [{100, 1}, {-1, 100}, {0, 1_000_001}, {1, 0xFFFFFFFF}, {0.5, 100}, {0, nil}] do
        assert Groups.random_roll(leader, minimum, maximum) == leader
        refute_received {:"$gen_cast", {:send_packet, %Message.MsgRandomRollResponse{}}}
      end
    end
  end

  describe "convert_raid/1" do
    test "projects conversion, assistant flags, and subgroup changes to both members", %{leader: leader, member: member} do
      assert Groups.convert_raid(member) == member
      refute PartySystem.group_of(leader.guid).raid?
      assert Groups.convert_raid(leader) == leader
      assert PartySystem.group_of(leader.guid).raid?
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPartyCommandResult{result: 0}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{group_type: 1, own_flags: 0}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{group_type: 1, own_flags: 0}}}

      Groups.set_assistant(leader, member.guid, true)
      assert Party.assistant?(PartySystem.group_of(leader.guid), member.guid)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{own_flags: 0, members: [%{flags: 128}]}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{own_flags: 128}}}
      Groups.change_subgroup(member, "Second", 7)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{own_flags: 135}}}
      assert Party.member(PartySystem.group_of(member.guid), member.guid).subgroup == 7
    end
  end

  describe "target_icon/3" do
    test "broadcasts authorized changes and returns the current list to any member", %{leader: leader, member: member} do
      Groups.target_icon(member, 7, 42)
      assert PartySystem.group_of(leader.guid).icons == %{}
      Groups.target_icon(leader, 7, 42)
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidTargetUpdateResponse{icon: 7, target: 42}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidTargetUpdateResponse{icon: 7, target: 42}}}
      Groups.target_icon(member, 255, nil)
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidTargetUpdateResponse{icons: [{7, 42}]}}}
    end
  end

  describe "ready_check/2" do
    test "requires management to start, includes offline members, and forwards answers to the leader", %{
      leader: leader,
      member: member
    } do
      offline = unique_guid()
      :ok = PartySystem.invite(leader.guid, "First", offline)
      {:ok, _} = PartySystem.accept(offline, "Offline")
      on_exit(fn -> PartySystem.leave(offline) end)
      Groups.ready_check(member, nil)
      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidReadyCheckResponse{}}}
      Groups.ready_check(leader, nil)
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidReadyCheckResponse{guid: nil}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidReadyCheckResponse{guid: nil}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidReadyCheckResponse{guid: ^offline, ready?: false}}}
      Groups.ready_check(member, true)
      member_guid = member.guid

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.MsgRaidReadyCheckResponse{guid: ^member_guid, ready?: true}}}

      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgRaidReadyCheckResponse{}}}
    end
  end

  defp party(_context) do
    leader = state(unique_guid())
    member = state(unique_guid())
    Registry.register(leader.guid)
    Registry.register(member.guid)
    :ok = PartySystem.invite(leader.guid, "First", member.guid)
    {:ok, _} = PartySystem.accept(member.guid, "Second")

    on_exit(fn ->
      PartySystem.leave(leader.guid)
      PartySystem.leave(member.guid)
    end)

    %{leader: leader, member: member}
  end

  defp state(guid) do
    %{
      ready: true,
      guid: guid,
      character: %Character{object: %Object{guid: guid}, internal: %Internal{world: WorldRef.open(0)}}
    }
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
