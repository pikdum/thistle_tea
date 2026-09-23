defmodule ThistleTea.Game.GuildTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Guild.Member

  describe "create/3" do
    test "reserves case-insensitive names and a unique founder" do
      founder = member(1, "Founder", 1)
      assert {:ok, group, guilds} = Guild.create(%Guild{}, founder, "The Fellowship")
      assert group.id == 1
      assert group.leader == 1
      assert Guild.member(group, 1).rank == 0
      assert Guild.group_by_name(guilds, "the fellowship") == group
      assert {:error, :name_exists} = Guild.create(guilds, member(2, "Other", 1), "THE FELLOWSHIP")
      assert {:error, :already_in_guild} = Guild.create(guilds, founder, "Another Guild")
      assert {:error, :invalid_name} = Guild.create(guilds, member(2, "Other", 1), "X")
    end
  end

  describe "invite/3" do
    test "applies faction, pending-invite, and rank permissions at the owner" do
      founder = member(1, "Founder", 1)
      ally = member(2, "Ally", 3)
      enemy = member(3, "Enemy", 2)
      {:ok, _group, guilds} = Guild.create(%Guild{}, founder, "Fellowship")

      assert {:error, :wrong_faction} = Guild.invite(guilds, 1, enemy)
      assert {:ok, _group, guilds} = Guild.invite(guilds, 1, ally)
      assert Guild.invited?(guilds, ally.guid)
      assert {:error, :already_invited} = Guild.invite(guilds, 1, ally)
      assert {:ok, group, guilds} = Guild.accept(guilds, ally)
      refute Guild.invited?(guilds, ally.guid)
      assert Guild.member(group, 2).rank == 4
      assert {:error, :permissions} = Guild.invite(guilds, 2, member(4, "Third", 1))
      assert {:error, :already_in_guild} = Guild.invite(guilds, 1, ally)
      assert {:error, :not_invited} = Guild.accept(guilds, member(4, "Third", 1))
    end
  end

  describe "set_leader/3" do
    test "transfers the sole leader rank and preserves permission ordering" do
      guilds = guild_with_members()
      assert {:error, :leader_cannot_leave} = Guild.leave(guilds, 1)
      assert {:error, :permissions} = Guild.set_leader(guilds, 2, 1)
      assert {:error, :permissions} = Guild.remove(guilds, 2, 1)

      assert {:ok, group, guilds} = Guild.set_leader(guilds, 1, 2)
      assert group.leader == 2
      assert Guild.member(group, 2).rank == 0
      assert Guild.member(group, 1).rank == 1
      assert {:error, :leader_cannot_leave} = Guild.leave(guilds, 2)
      assert {:ok, group, guilds} = Guild.leave(guilds, 1)
      assert Map.keys(group.members) == [2]
      assert Guild.group_of(guilds, 1) == nil
    end
  end

  describe "edit_rank/5" do
    test "keeps founder rights and shifts members when deleting a rank" do
      guilds = guild_with_members()

      assert {:error, :permissions} = Guild.add_rank(guilds, 2, "Scout")
      assert {:ok, group, guilds} = Guild.add_rank(guilds, 1, "Scout")
      assert length(group.ranks) == 6
      assert {:ok, group, guilds} = Guild.edit_rank(guilds, 1, 0, 0, "Captain")
      assert hd(group.ranks).rights == 0xFF1FF
      assert {:ok, group, guilds} = Guild.edit_rank(guilds, 1, 5, 0x50, "Recruit")
      assert Enum.at(group.ranks, 5).rights == 0x50
      assert {:error, :invalid_name} = Guild.edit_rank(guilds, 1, 5, 0x50, String.duplicate("X", 16))

      new_member = member(3, "Third", 1)
      assert {:ok, _group, guilds} = Guild.invite(guilds, 1, new_member)
      assert {:ok, group, guilds} = Guild.accept(guilds, new_member)
      assert Guild.member(group, 3).rank == 5
      assert {:ok, group, guilds} = Guild.delete_rank(guilds, 1)
      assert length(group.ranks) == 5
      assert Guild.member(group, 3).rank == 4
      assert {:error, :rank_too_low} = Guild.delete_rank(guilds, 1)
    end
  end

  describe "set_emblem/3" do
    test "only the guild leader can set valid tabard colors" do
      guilds = guild_with_members()
      emblem = {3, 4, 5, 6, 7}

      assert {:error, :permissions} = Guild.set_emblem(guilds, 2, emblem)
      assert {:error, :invalid_emblem} = Guild.set_emblem(guilds, 1, {256, 4, 5, 6, 7})
      assert {:ok, group, updated} = Guild.set_emblem(guilds, 1, emblem)
      assert group.emblem == emblem
      assert Guild.group_of(updated, 2).emblem == emblem
    end
  end

  describe "disband/2" do
    test "clears membership, names, and pending invitations together" do
      guilds = guild_with_members()
      {:ok, _group, guilds} = Guild.invite(guilds, 1, member(3, "Third", 1))

      assert {:error, :permissions} = Guild.disband(guilds, 2)
      assert {:ok, _group, guilds} = Guild.disband(guilds, 1)
      assert Guild.group_of(guilds, 1) == nil
      assert Guild.group_of(guilds, 2) == nil
      assert Guild.group_by_name(guilds, "Fellowship") == nil
      assert {:error, :not_invited} = Guild.accept(guilds, member(3, "Third", 1))
    end

    test "leaving a one-member guild disbands it" do
      {:ok, group, guilds} = Guild.create(%Guild{}, member(1, "Founder", 1), "Fellowship")

      assert {:ok, ^group, guilds} = Guild.leave(guilds, 1)
      assert Guild.group_of(guilds, 1) == nil
      assert Guild.group_by_name(guilds, "Fellowship") == nil
    end
  end

  defp guild_with_members do
    {:ok, _group, guilds} = Guild.create(%Guild{}, member(1, "Founder", 1), "Fellowship")
    {:ok, _group, guilds} = Guild.invite(guilds, 1, member(2, "Ally", 1))
    {:ok, _group, guilds} = Guild.accept(guilds, member(2, "Ally", 1))
    guilds
  end

  defp member(guid, name, race), do: %Member{guid: guid, name: name, race: race, class: 1, level: 1}
end
