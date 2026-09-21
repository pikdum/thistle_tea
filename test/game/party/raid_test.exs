defmodule ThistleTea.Game.Party.RaidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member

  setup [:party]

  describe "convert_raid/2" do
    test "preserves membership and loot while expanding to eight groups of five", %{party: party} do
      {:ok, before, party} = Party.set_loot(party, 1, 2, 2, 4)
      assert {:error, :not_leader} = Party.convert_raid(party, 2)
      {:ok, raid, party} = Party.convert_raid(party, 1)
      assert raid == %{before | raid?: true}
      assert Party.max_members(raid) == 40
      assert Party.max_members(before) == 5

      party = Enum.reduce(3..40, party, &join(&2, 1, &1))
      raid = Party.group_of(party, 1)
      assert Enum.map(raid.members, & &1.guid) == Enum.to_list(1..40)
      assert Enum.frequencies_by(raid.members, & &1.subgroup) == Map.new(0..7, &{&1, 5})
      assert {:error, :group_full} = Party.invite(party, 1, "Member1", 41)
      assert {:ok, ^raid, ^party} = Party.convert_raid(party, 1)
    end
  end

  describe "set_assistant/4" do
    test "grants management while keeping leadership and loot restricted", %{party: party} do
      {:ok, _, party} = Party.convert_raid(party, 1)
      {:ok, group, party} = Party.set_assistant(party, 1, 2, true)
      assert Party.member_flags(Party.member(group, 2)) == 0x80
      assert Party.manager?(group, 2)
      party = join(party, 2, 3)
      assert {:error, :not_leader} = Party.set_assistant(party, 2, 3, true)
      assert {:error, :not_leader} = Party.set_leader(party, 2, 3)
      assert {:error, :not_leader} = Party.set_loot(party, 2, 0, 0, 2)
      assert {:error, :not_leader} = Party.uninvite(party, 2, 1)
      assert {:ok, {:removed, _, false}, _} = Party.uninvite(party, 2, 3)

      {:ok, _, party} = Party.set_assistant(party, 1, 2, false)
      assert {:error, :not_leader} = Party.invite(party, 2, "Member2", 4)
    end
  end

  describe "change_subgroup/4" do
    test "rejects invalid moves and swaps full subgroups atomically", %{party: party} do
      {:ok, _, party} = Party.convert_raid(party, 1)
      party = Enum.reduce(3..10, party, &join(&2, 1, &1))
      assert {:error, :invalid_subgroup} = Party.change_subgroup(party, 1, 2, 8)
      assert {:error, :not_leader} = Party.change_subgroup(party, 2, 2, 2)
      assert {:error, :target_not_in_group} = Party.change_subgroup(party, 1, 99, 2)
      assert {:error, :group_full} = Party.change_subgroup(party, 1, 2, 1)
      {:ok, group, party} = Party.swap_subgroups(party, 1, 2, 6)
      assert Party.member(group, 2).subgroup == 1
      assert Party.member(group, 6).subgroup == 0
      assert Enum.frequencies_by(group.members, & &1.subgroup) == %{0 => 5, 1 => 5}
      {:ok, group, _} = Party.change_subgroup(party, 1, 2, 7)
      assert Party.subgroup_members(group, 2) == [%Member{guid: 2, name: "Member2", subgroup: 7}]
      assert Party.subgroup_members(group, 99) == []
    end
  end

  describe "set_icon/4" do
    test "keeps one icon per target and allows ordinary party leaders", %{party: party} do
      {:ok, _, [{0, 50}], party} = Party.set_icon(party, 1, 0, 50)
      {:ok, group, [{0, 0}, {7, 50}], party} = Party.set_icon(party, 1, 7, 50)
      assert group.icons == %{7 => 50}
      assert {:error, :not_leader} = Party.set_icon(party, 2, 1, 51)
      assert {:error, :invalid_icon} = Party.set_icon(party, 1, 8, 51)
      {:ok, group, [{7, 0}], _} = Party.set_icon(party, 1, 7, 0)
      assert group.icons == %{}
    end
  end

  describe "leave/2" do
    test "pending invitations stay with the original raid and disappear on disband", %{party: party} do
      {:ok, _, party} = Party.convert_raid(party, 1)
      party = join(party, 1, 3)
      {:ok, _, party} = Party.set_assistant(party, 1, 2, true)
      {:ok, party} = Party.invite(party, 2, "Member2", 4)
      assert {:error, :already_in_group} = Party.invite(party, 4, "Member4", 5)
      {:ok, {:removed, raid, false}, party} = Party.leave(party, 2)
      {:ok, joined, party} = Party.accept(party, 4, "Member4")
      assert joined.id == raid.id
      assert joined.leader == 1
      refute Party.in_group?(party, 2)
      {:ok, party} = Party.invite(party, 1, "Member1", 5)
      {:ok, _, party} = Party.leave(party, 3)
      {:ok, {:disbanded, _}, party} = Party.leave(party, 4)
      assert party.invites == %{}
      assert {:error, :not_invited} = Party.accept(party, 5, "Member5")
    end

    test "retains raid mode on leadership transfer and removes the final group", %{party: party} do
      {:ok, _, party} = Party.convert_raid(party, 1)
      party = join(party, 1, 3)
      {:ok, {:removed, %Group{leader: 2, raid?: true}, true}, party} = Party.leave(party, 1)
      {:ok, {:disbanded, _}, party} = Party.leave(party, 3)
      assert party.groups == %{}
      assert party.member_index == %{}
    end
  end

  defp party(_context), do: %{party: join(%Party{}, 1, 2)}

  defp join(party, inviter, invitee) do
    {:ok, party} = Party.invite(party, inviter, "Member#{inviter}", invitee)
    {:ok, _, party} = Party.accept(party, invitee, "Member#{invitee}")
    party
  end
end
