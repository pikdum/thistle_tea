defmodule ThistleTea.Game.Player.GroupsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Groups
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:party]

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
