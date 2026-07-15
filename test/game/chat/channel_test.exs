defmodule ThistleTea.Game.Chat.ChannelTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Chat.Channel
  alias ThistleTea.Game.Chat.Channel.Member

  @definition %{kind: :custom, flags: 0x01}

  describe "join/3" do
    test "makes the first custom-channel member owner and moderator" do
      channel = channel()
      {:ok, channel, outcome} = Channel.join(channel, member(1, "Owner"), "")

      assert channel.owner_guid == 1
      assert outcome.owner_assigned?
      assert band(outcome.member.flags, Channel.owner_flag()) != 0
      assert band(outcome.member.flags, Channel.moderator_flag()) != 0
    end

    test "enforces the channel password" do
      channel = %{channel() | password: "tea"}

      assert {:error, :wrong_password} = Channel.join(channel, member(1, "Guest"), "coffee")
      assert {:ok, _channel, _outcome} = Channel.join(channel, member(1, "Guest"), "tea")
    end

    test "rejects banned members" do
      channel = %{channel() | banned: MapSet.new([1])}
      assert {:error, :banned} = Channel.join(channel, member(1, "Banned"), "")
    end
  end

  describe "leave/2" do
    test "transfers ownership deterministically" do
      channel = joined_channel([member(3, "Owner"), member(2, "Second"), member(4, "Third")])
      {:ok, channel, outcome} = Channel.leave(channel, 3)

      assert channel.owner_guid == 2
      assert outcome.owner_change.member.guid == 2
      assert Channel.owner?(outcome.owner_change.member)
      assert Channel.moderator?(outcome.owner_change.member)
    end
  end

  describe "speak/2" do
    test "requires membership" do
      assert {:error, :not_member} = Channel.speak(channel(), 1)
    end

    test "rejects muted members" do
      channel = joined_channel([member(1, "Owner"), member(2, "Muted")])
      {:ok, channel, _outcome} = Channel.set_mode(channel, 1, "Muted", :muted, true)

      assert {:error, :muted} = Channel.speak(channel, 2)
    end

    test "enforces moderation while allowing moderators" do
      channel = joined_channel([member(1, "Owner"), member(2, "Guest")])
      {:ok, channel} = Channel.toggle_moderation(channel, 1)

      assert {:error, :not_moderator} = Channel.speak(channel, 2)
      assert {:ok, _members} = Channel.speak(channel, 1)
    end
  end

  describe "ownership and moderation" do
    test "only the owner can transfer ownership" do
      channel = joined_channel([member(1, "Owner"), member(2, "Guest")])

      assert {:error, :not_owner} = Channel.set_owner(channel, 2, "Guest")
      assert {:ok, channel, _outcome} = Channel.set_owner(channel, 1, "Guest")
      assert channel.owner_guid == 2
    end

    test "moderators cannot change the owner" do
      channel = joined_channel([member(1, "Owner"), member(2, "Moderator")])
      {:ok, channel, _outcome} = Channel.set_mode(channel, 1, "Moderator", :moderator, true)

      assert {:error, :not_owner} = Channel.set_mode(channel, 2, "Owner", :muted, true)
    end

    test "banning removes the member and prevents rejoining" do
      target = member(2, "Target")
      channel = joined_channel([member(1, "Owner"), target])
      {:ok, channel, outcome} = Channel.kick(channel, 1, "Target", true)

      assert outcome.target.guid == 2
      assert {:error, :banned} = Channel.join(channel, target, "")
    end
  end

  defp channel do
    Channel.new({:alliance, "custom"}, "Custom", :alliance, @definition)
  end

  defp joined_channel(members) do
    Enum.reduce(members, channel(), fn member, channel ->
      {:ok, channel, _outcome} = Channel.join(channel, member, "")
      channel
    end)
  end

  defp member(guid, name), do: %Member{guid: guid, name: name, team: :alliance}
end
