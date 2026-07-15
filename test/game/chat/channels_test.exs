defmodule ThistleTea.Game.Chat.ChannelsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Chat.Channel.Member
  alias ThistleTea.Game.Chat.Channels

  @definition %{kind: :custom, flags: 0x01}

  describe "join/5" do
    test "canonicalizes names while separating factions" do
      alliance = member(1, "Alliance", :alliance)
      horde = member(2, "Horde", :horde)

      {:ok, alliance_channel, _outcome, channels} = Channels.join(%Channels{}, alliance, " Tea ", "", @definition)
      {:ok, horde_channel, _outcome, channels} = Channels.join(channels, horde, "tea", "", @definition)

      assert alliance_channel.key == {:alliance, "tea"}
      assert horde_channel.key == {:horde, "tea"}
      assert map_size(channels.channels) == 2
    end
  end

  describe "leave_all/2" do
    test "removes every membership and deletes empty channels" do
      actor = member(1, "Owner", :alliance)
      {:ok, _channel, _outcome, channels} = Channels.join(%Channels{}, actor, "One", "", @definition)
      {:ok, _channel, _outcome, channels} = Channels.join(channels, actor, "Two", "", @definition)

      {outcomes, channels} = Channels.leave_all(channels, actor.guid)

      assert length(outcomes) == 2
      assert channels.channels == %{}
      assert channels.memberships == %{}
    end
  end

  defp member(guid, name, team), do: %Member{guid: guid, name: name, team: team}
end
