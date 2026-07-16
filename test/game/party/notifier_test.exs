defmodule ThistleTea.Game.Party.NotifierTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member
  alias ThistleTea.Game.Party.Notifier

  describe "send_group_list/2" do
    test "marks the leader before sending the roster" do
      guid = System.unique_integer([:positive])
      {:ok, _owner} = EntityRegistry.register(guid)
      on_exit(fn -> EntityRegistry.unregister(guid) end)
      group = %Group{id: 1, leader: guid, members: [%Member{guid: guid, name: "Leader"}]}

      Notifier.send_group_list(group, guid)

      assert_receive {:"$gen_cast", {:party_leader_changed, true}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{leader: ^guid}}}
    end

    test "clears leadership before sending an empty roster" do
      guid = System.unique_integer([:positive])
      {:ok, _owner} = EntityRegistry.register(guid)
      on_exit(fn -> EntityRegistry.unregister(guid) end)

      Notifier.send_empty_group_list(guid)

      assert_receive {:"$gen_cast", {:party_leader_changed, false}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupList{}}}
    end
  end
end
