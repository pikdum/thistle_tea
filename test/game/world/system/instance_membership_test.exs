defmodule ThistleTea.Game.World.System.InstanceMembershipTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.System.Instance
  alias ThistleTea.Game.World.System.Party

  setup [:build_members]

  describe "group_changed/3" do
    test "adopts copies, notifies kicked players, and restores rejoined members", %{
      guids: [leader, member, third],
      map: map
    } do
      {:ok, world} = Instance.enter(map, leader)
      :ok = Party.invite(leader, "Leader", member)
      {:ok, group} = Party.accept(member, "Member")
      assert Instance.world_for(map, member) == world
      assert {:ok, ^world} = Instance.enter(map, member)
      :ok = Party.invite(leader, "Leader", third)
      {:ok, _group} = Party.accept(third, "Third")
      assert Instance.valid_member?(world, member)
      assert_receive {:"$gen_cast", {:instance_membership_changed, ^world}}

      assert {:ok, {:removed, _, false}} = Party.uninvite(leader, member)
      assert_receive {:"$gen_cast", {:instance_membership_changed, ^world}}
      refute Instance.valid_member?(world, member)
      assert Instance.valid_member?(world, leader)
      assert {:error, :instance_unavailable} = Instance.resume(world, member)
      assert Instance.info(member).current == world

      :ok = Party.invite(leader, "Leader", member)
      {:ok, rejoined} = Party.accept(member, "Member")
      assert rejoined.id == group.id
      assert Instance.valid_member?(world, member)
      Instance.leave(member, world)
      assert {:ok, ^world} = Instance.resume(world, member)

      {:ok, _} = Party.leave(third)
      {:ok, {:disbanded, _}} = Party.leave(member)
      refute Instance.valid_member?(world, leader)
      refute Instance.valid_member?(world, member)
      :ok = Party.invite(leader, "Leader", member)
      {:ok, reformed} = Party.accept(member, "Member")
      refute reformed.id == group.id
      assert Instance.world_for(map, leader) == world
      assert Instance.valid_member?(world, member)
      assert Instance.valid_member?(world, leader)
    end
  end

  defp build_members(_context) do
    map = 900_003
    :ets.insert(MapTemplate, {map, 1, nil})
    guids = Enum.map(1..3, fn _ -> System.unique_integer([:positive]) + 10_000_000 end)
    [_leader, member, _third] = guids
    Entity.register(member)
    on_exit(fn -> cleanup_members(guids, map) end)
    %{map: map, guids: guids}
  end

  defp cleanup_members([leader, member, _third] = guids, map) do
    Enum.each(guids, fn guid ->
      if world = Instance.info(guid).current, do: Instance.leave(guid, world)
    end)

    if is_nil(Party.group_of(leader)) do
      Party.leave(member)
      :ok = Party.invite(leader, "Leader", member)
      Party.accept(member, "Member")
    end

    Instance.reset(leader)
    Enum.each(guids, &Party.leave/1)
    :ets.delete(MapTemplate, map)
  end
end
