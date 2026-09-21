defmodule ThistleTea.Game.World.System.ChatChannelsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Chat.Channel.Member
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Social
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SocialStore
  alias ThistleTea.Game.World.System.ChatChannels

  describe "join/3" do
    test "sends built-in channel metadata from the catalog" do
      actor = member("Catalog")
      receiver = start_receiver(actor.guid, :actor)

      assert :ok = ChatChannels.join(actor, "General - Elwynn Forest", "")

      assert_receive {:actor, {:"$gen_cast", {:send_packet, %Message.SmsgChannelNotify{} = packet}}}
      assert packet.notify_type == Message.SmsgChannelNotify.notice(:you_joined)
      assert packet.channel_flags == 0x18
      assert packet.channel_index == 0

      cleanup([actor], [receiver])
    end

    test "enforces custom-channel passwords" do
      owner = member("Owner")
      guest = member("Guest")
      receivers = [start_receiver(owner.guid, :owner), start_receiver(guest.guid, :guest)]
      channel_name = unique_name("Password")

      assert :ok = ChatChannels.join(owner, channel_name, "")
      drain_mailbox()
      assert :ok = ChatChannels.password(owner, channel_name, "tea")
      drain_mailbox()

      assert {:error, :wrong_password} = ChatChannels.join(guest, channel_name, "coffee")

      assert_receive {:guest, {:"$gen_cast", {:send_packet, %Message.SmsgChannelNotify{} = packet}}}
      assert packet.notify_type == Message.SmsgChannelNotify.notice(:wrong_password)

      assert :ok = ChatChannels.join(guest, channel_name, "tea")
      cleanup([owner, guest], receivers)
    end
  end

  describe "say/4" do
    test "filters ignored senders while preserving moderator delivery" do
      owner = member("Owner")
      sender = member("Sender")
      target = member("Target")
      actors = [owner, sender, target]

      receivers = [
        start_receiver(owner.guid, :owner),
        start_receiver(sender.guid, :sender),
        start_receiver(target.guid, :target)
      ]

      channel = unique_name("Ignored")

      on_exit(fn ->
        cleanup(actors, receivers)
        :ets.delete(SocialStore, target.guid)
      end)

      for actor <- actors, do: ChatChannels.join(actor, channel, "")
      {:ok, social} = Social.add(SocialStore.get(target.guid), :ignore, sender.guid)
      SocialStore.put(social)
      assert :ok = ChatChannels.say(sender, channel, 7, "filtered")
      assert_receive {:owner, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "filtered"}}}}
      assert_receive {:sender, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "filtered"}}}}
      refute_receive {:target, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "filtered"}}}}

      assert :ok = ChatChannels.set_moderator(owner, channel, sender.name, true)
      assert :ok = ChatChannels.say(sender, channel, 7, "moderator")
      assert_receive {:target, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "moderator"}}}}
      social |> Social.remove(:ignore, sender.guid) |> SocialStore.put()
      assert :ok = ChatChannels.set_moderator(owner, channel, sender.name, false)
      assert :ok = ChatChannels.say(sender, channel, 7, "restored")
      assert_receive {:target, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "restored"}}}}
    end

    test "uses the current chat tag after joining" do
      actor = member("Status")
      receiver = start_receiver(actor.guid, :actor)
      channel = unique_name("Status")
      assert :ok = ChatChannels.join(actor, channel, "")
      drain_mailbox()

      for tag <- [1, 2, 0] do
        assert :ok = ChatChannels.say(%{actor | chat_tag: tag}, channel, 7, "hello")

        assert_receive {:actor, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "hello", tag: ^tag}}}}
      end

      cleanup([actor], [receiver])
    end

    test "rejects non-members instead of broadcasting" do
      actor = member("Outsider")
      receiver = start_receiver(actor.guid, :actor)

      assert {:error, :not_member} = ChatChannels.say(actor, unique_name("Missing"), 0, "hello")

      assert_receive {:actor, {:"$gen_cast", {:send_packet, %Message.SmsgChannelNotify{} = packet}}}
      assert packet.notify_type == Message.SmsgChannelNotify.notice(:not_member)
      refute_receive {:actor, {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{}}}}

      cleanup([actor], [receiver])
    end
  end

  describe "invite/3" do
    test "acknowledges the inviter while suppressing an ignored invitation" do
      owner = member("Owner")
      target = member("Target")
      receivers = [start_receiver(owner.guid, :owner), start_receiver(target.guid, :target)]
      channel = unique_name("Invite")
      Metadata.put(target.guid, %{name: target.name, race: 1})

      on_exit(fn ->
        cleanup([owner, target], receivers)
        :ets.delete(SocialStore, target.guid)
        Metadata.delete(target.guid)
      end)

      ChatChannels.join(owner, channel, "")
      {:ok, social} = Social.add(SocialStore.get(target.guid), :ignore, owner.guid)
      SocialStore.put(social)
      assert :ok = ChatChannels.invite(owner, channel, target.name)
      invited = Message.SmsgChannelNotify.notice(:player_invited)
      invite = Message.SmsgChannelNotify.notice(:invite)
      assert_receive {:owner, {:"$gen_cast", {:send_packet, %Message.SmsgChannelNotify{notify_type: ^invited}}}}
      refute_receive {:target, {:"$gen_cast", {:send_packet, %Message.SmsgChannelNotify{notify_type: ^invite}}}}
      social |> Social.remove(:ignore, owner.guid) |> SocialStore.put()
      assert :ok = ChatChannels.invite(owner, channel, target.name)
      assert_receive {:target, {:"$gen_cast", {:send_packet, %Message.SmsgChannelNotify{notify_type: ^invite}}}}
    end
  end

  defp member(prefix) do
    id = System.unique_integer([:positive, :monotonic])
    %Member{guid: id, name: "#{prefix}#{id}", team: :alliance}
  end

  defp unique_name(prefix), do: "#{prefix}#{System.unique_integer([:positive, :monotonic])}"

  defp start_receiver(guid, label) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _owner} = EntityRegistry.register(guid)
        send(parent, {:registered, label})
        receiver_loop(parent, label)
      end)

    assert_receive {:registered, ^label}
    pid
  end

  defp receiver_loop(parent, label) do
    receive do
      message ->
        send(parent, {label, message})
        receiver_loop(parent, label)
    end
  end

  defp cleanup(actors, receivers) do
    Enum.each(actors, &ChatChannels.leave_all(&1.guid))
    Enum.each(receivers, &Process.exit(&1, :kill))
    drain_mailbox()
  end

  defp drain_mailbox do
    receive do
      _message -> drain_mailbox()
    after
      0 -> :ok
    end
  end
end
