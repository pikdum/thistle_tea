defmodule ThistleTea.Game.PartyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Group

  defp invite_and_accept(party, inviter, inviter_name, invitee, invitee_name) do
    {:ok, party} = Party.invite(party, inviter, inviter_name, invitee)
    {:ok, group, party} = Party.accept(party, invitee, invitee_name)
    {group, party}
  end

  defp full_group do
    party = %Party{}
    {_group, party} = invite_and_accept(party, 1, "Leader", 2, "Second")

    Enum.reduce(3..5, party, fn guid, party ->
      {_group, party} = invite_and_accept(party, 1, "Leader", guid, "Member#{guid}")
      party
    end)
  end

  describe "invite/4" do
    test "stores a pending invite" do
      {:ok, party} = Party.invite(%Party{}, 1, "Leader", 2)
      assert Party.invited?(party, 2)
    end

    test "rejects an invitee who is already invited" do
      {:ok, party} = Party.invite(%Party{}, 1, "Leader", 2)
      assert {:error, :already_in_group} = Party.invite(party, 3, "Other", 2)
    end

    test "rejects an invitee who is already in a group" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:error, :already_in_group} = Party.invite(party, 3, "Other", 2)
    end

    test "rejects invites from non-leaders" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:error, :not_leader} = Party.invite(party, 2, "Second", 3)
    end

    test "rejects invites when the group is full" do
      party = full_group()
      assert {:error, :group_full} = Party.invite(party, 1, "Leader", 6)
    end
  end

  describe "accept/3" do
    test "creates a group on first accept with inviter as leader" do
      {group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")

      assert %Group{leader: 1} = group
      assert Enum.map(group.members, & &1.guid) == [1, 2]
      assert Party.in_group?(party, 1)
      assert Party.in_group?(party, 2)
      refute Party.invited?(party, 2)
    end

    test "joins the inviter's existing group" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      {group, _party} = invite_and_accept(party, 1, "Leader", 3, "Third")

      assert Enum.map(group.members, & &1.guid) == [1, 2, 3]
      assert group.leader == 1
    end

    test "fails without a pending invite" do
      assert {:error, :not_invited} = Party.accept(%Party{}, 2, "Second")
    end

    test "fails when the group filled up after the invite" do
      party = full_group()
      party = %{party | invites: Map.put(party.invites, 6, %{inviter: 1, inviter_name: "Leader"})}
      assert {:error, :group_full} = Party.accept(party, 6, "Sixth")
    end
  end

  describe "decline/2" do
    test "removes the invite and returns the inviter" do
      {:ok, party} = Party.invite(%Party{}, 1, "Leader", 2)
      assert {:ok, 1, party} = Party.decline(party, 2)
      refute Party.invited?(party, 2)
    end

    test "fails without a pending invite" do
      assert {:error, :not_invited} = Party.decline(%Party{}, 2)
    end
  end

  describe "leave/2" do
    test "disbands a two-member group" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:ok, {:disbanded, group}, party} = Party.leave(party, 2)

      assert Enum.map(group.members, & &1.guid) == [1, 2]
      refute Party.in_group?(party, 1)
      refute Party.in_group?(party, 2)
    end

    test "removes a member from a larger group" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      {_group, party} = invite_and_accept(party, 1, "Leader", 3, "Third")

      assert {:ok, {:removed, group, false}, party} = Party.leave(party, 2)
      assert Enum.map(group.members, & &1.guid) == [1, 3]
      refute Party.in_group?(party, 2)
      assert Party.in_group?(party, 3)
    end

    test "transfers leadership when the leader leaves" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      {_group, party} = invite_and_accept(party, 1, "Leader", 3, "Third")

      assert {:ok, {:removed, group, true}, _party} = Party.leave(party, 1)
      assert group.leader == 2
    end

    test "fails when not in a group" do
      assert {:error, :not_in_group} = Party.leave(%Party{}, 1)
    end
  end

  describe "uninvite/3" do
    test "removes the target from the group" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      {_group, party} = invite_and_accept(party, 1, "Leader", 3, "Third")

      assert {:ok, {:removed, group, false}, _party} = Party.uninvite(party, 1, 3)
      assert Enum.map(group.members, & &1.guid) == [1, 2]
    end

    test "cancels a pending invite" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      {:ok, party} = Party.invite(party, 1, "Leader", 3)

      assert {:ok, :invite_cancelled, party} = Party.uninvite(party, 1, 3)
      refute Party.invited?(party, 3)
    end

    test "requires leadership" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:error, :not_leader} = Party.uninvite(party, 2, 1)
    end

    test "fails when the target is not in the group" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:error, :target_not_in_group} = Party.uninvite(party, 1, 99)
    end
  end

  describe "set_leader/3" do
    test "transfers leadership" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:ok, group, _party} = Party.set_leader(party, 1, 2)
      assert group.leader == 2
    end

    test "requires current leadership" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:error, :not_leader} = Party.set_leader(party, 2, 2)
    end
  end

  describe "set_loot/5" do
    test "updates loot settings for the leader" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:ok, group, _party} = Party.set_loot(party, 1, 2, 1, 3)
      assert group.loot_method == 2
      assert group.master_looter == 1
      assert group.loot_threshold == 3
    end

    test "requires leadership" do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      assert {:error, :not_leader} = Party.set_loot(party, 2, 0, 0, 2)
    end
  end

  describe "update_looter/3" do
    setup do
      {_group, party} = invite_and_accept(%Party{}, 1, "Leader", 2, "Second")
      {group, party} = invite_and_accept(party, 1, "Leader", 3, "Third")
      %{party: party, group_id: group.id}
    end

    test "rotates through eligible members in member order", %{party: party, group_id: group_id} do
      {looter, party} = Party.update_looter(party, group_id, [1, 2, 3])
      assert looter == 1

      {looter, party} = Party.update_looter(party, group_id, [1, 2, 3])
      assert looter == 2

      {looter, party} = Party.update_looter(party, group_id, [1, 2, 3])
      assert looter == 3

      {looter, _party} = Party.update_looter(party, group_id, [1, 2, 3])
      assert looter == 1
    end

    test "skips ineligible members", %{party: party, group_id: group_id} do
      {looter, party} = Party.update_looter(party, group_id, [2])
      assert looter == 2

      {looter, _party} = Party.update_looter(party, group_id, [1, 3])
      assert looter == 3
    end

    test "returns nil when nobody is eligible", %{party: party, group_id: group_id} do
      assert {nil, _party} = Party.update_looter(party, group_id, [])
    end

    test "returns nil for an unknown group", %{party: party} do
      assert {nil, _party} = Party.update_looter(party, 999, [1])
    end
  end

  describe "same_team?/2" do
    test "alliance races group together" do
      assert Party.same_team?(1, 7)
    end

    test "horde races group together" do
      assert Party.same_team?(2, 8)
    end

    test "cross-faction grouping is rejected" do
      refute Party.same_team?(1, 2)
    end
  end
end
