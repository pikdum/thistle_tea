defmodule ThistleTea.Game.Instance.MembershipTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.Instance.Admission.Actor
  alias ThistleTea.Game.Instance.Admission.Policy
  alias ThistleTea.Game.Party.Group

  describe "group_changed/3" do
    test "adopts the leader's copies without replacing progress or entry history" do
      actor = %Actor{guid: 1, account: 1}

      {:ok, world, _, instances} =
        Instance.admit(%Instance{}, 329, {:player, 1}, actor, %Policy{}, 0, "instance_stratholme")

      {:ok, 2, [], instances} = Instance.command(instances, world, 7, 2, :raw)
      history = instances.entry_history
      grouped = Instance.group_changed(instances, nil, %Group{id: 10, leader: 1})

      assert Instance.world_for(grouped, 329, {:player, 1}) == nil
      assert Instance.world_for(grouped, 329, {:party, 10}) == world
      assert Instance.read(grouped, world, 7) == {:ok, 2}
      assert grouped.entry_history == history
      assert grouped.next_id == instances.next_id
      assert Instance.valid_member?(grouped, world, {:party, 10}, actor, %Policy{})
    end

    test "selects the group copy over a joining member's old solo copy" do
      {leader_world, _, instances} = Instance.enter(%Instance{}, 389, {:player, 1}, 1)
      {member_world, _, instances} = Instance.enter(instances, 389, {:player, 2}, 2)
      instances = Instance.group_changed(instances, nil, %Group{id: 10, leader: 1})
      assert {^leader_world, ^member_world, instances} = Instance.enter(instances, 389, {:party, 10}, 2)
      assert Instance.empty?(instances, member_world)
      assert Instance.member_world(instances, 2) == leader_world
    end

    test "disbanding invalidates members and reforming adopts the same copy" do
      group = %Group{id: 10, leader: 1}
      {world, _, instances} = Instance.enter(%Instance{}, 389, {:party, 10}, 1)
      {^world, _, instances} = Instance.enter(instances, 389, {:party, 10}, 2)
      instances = Instance.group_changed(instances, group, nil)
      assert Instance.copy(instances, world).orphaned?
      refute Instance.owned_by?(instances, world, {:party, 10})
      assert Instance.member_world(instances, 1) == world

      instances = Instance.group_changed(instances, nil, %Group{id: 11, leader: 1})
      refute Instance.copy(instances, world).orphaned?
      assert Instance.world_for(instances, 389, {:party, 10}) == nil
      assert Instance.owned_by?(instances, world, {:party, 11})
      assert Instance.valid_member?(instances, world, {:party, 11}, %Actor{guid: 2, account: 2}, %Policy{})
      refute Instance.valid_member?(instances, world, {:player, 2}, %Actor{guid: 2, account: 2}, %Policy{})
    end

    test "cannot adopt a copy still owned by another active group" do
      {world, _, instances} = Instance.enter(%Instance{}, 389, {:party, 10}, 1)
      updated = Instance.group_changed(instances, nil, %Group{id: 11, leader: 1})
      assert updated == instances
      assert Instance.owned_by?(updated, world, {:party, 10})
      assert Instance.world_for(updated, 389, {:party, 11}) == nil
    end
  end

  describe "valid_member?/5" do
    test "requires current ownership and raid membership without counting admission again" do
      actor = %Actor{guid: 1, account: 1, raid?: true}
      {world, _, instances} = Instance.enter(%Instance{}, 309, {:party, 10}, 1)
      assert Instance.valid_member?(instances, world, {:party, 10}, actor, %Policy{raid?: true})
      refute Instance.valid_member?(instances, world, {:player, 1}, actor, %Policy{raid?: true})
      refute Instance.valid_member?(instances, world, {:party, 10}, %{actor | raid?: false}, %Policy{raid?: true})
      refute Instance.valid_member?(instances, world, {:party, 10}, %{actor | guid: 2}, %Policy{raid?: true})
      {instances, ^world} = Instance.leave(instances, 1, world)
      refute Instance.valid_member?(instances, world, {:party, 10}, actor, %Policy{raid?: true})
    end
  end
end
