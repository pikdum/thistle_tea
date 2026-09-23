defmodule ThistleTea.Game.Instance.LockoutsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.Instance.Admission.Actor
  alias ThistleTea.Game.Instance.Admission.Policy
  alias ThistleTea.Game.Instance.Lockouts
  alias ThistleTea.Game.Party.Group

  setup [:build_raid]

  describe "bind_raid/3" do
    test "saves only present players and binds the killing group's present leader", %{
      instances: instances,
      world: world,
      group: group
    } do
      {[1, 2], saved} = bind(instances, world, group)
      assert Instance.saved_worlds(saved, 1) == [world]
      assert Instance.saved_worlds(saved, 2) == [world]
      assert Instance.saved_worlds(saved, 3) == []
      assert Lockouts.world_for(saved.lockouts, 249, {:party, 10}) == world
      assert {[], ^saved} = Instance.bind_raid(saved, world, group)
      {saved, nil} = Instance.leave(saved, 1, world)
      {saved, ^world} = Instance.leave(saved, 2, world)
      assert Instance.destroy_empty(saved, world) == saved
    end

    test "does not bind a group whose leader is outside", %{instances: instances, world: world, group: group} do
      {instances, nil} = Instance.leave(instances, 1, world)
      {[2], saved} = Instance.bind_raid(instances, world, group)
      assert Lockouts.world_for(saved.lockouts, 249, {:party, 10}) == nil
      assert Instance.saved_worlds(saved, 1) == []
      {:ok, ^world, nil, entered} = admit(saved, 3, 10)
      assert Instance.saved_worlds(entered, 3) == []
    end
  end

  describe "admit/7" do
    test "saves later entrants only after successful admission", %{instances: instances, world: world, group: group} do
      {_, saved} = Instance.bind_raid(instances, world, group)
      assert {:error, :instance_full} = admit(saved, 3, 10, %Policy{raid?: true, player_limit: 2})
      assert Instance.saved_worlds(saved, 3) == []
      {:ok, ^world, nil, entered} = admit(saved, 3, 10)
      assert Instance.saved_worlds(entered, 3) == [world]
    end

    test "rejects a different permanent save without changing membership or quota", %{
      instances: instances,
      world: world,
      group: group
    } do
      {_, instances} = Instance.bind_raid(instances, world, group)
      {:ok, other, nil, instances} = admit(instances, 3, 11)
      {_, instances} = Instance.bind_raid(instances, other, %Group{id: 11, leader: 3})
      assert {:error, :instance_unavailable} = admit(instances, 3, 10)
      assert Instance.member_world(instances, 3) == other
      assert Instance.saved_worlds(instances, 3) == [other]

      assert {:error, :instance_unavailable} =
               Instance.admit_copy(instances, actor(3), world, %Policy{raid?: true}, 100)
    end

    test "lets a saved member bring an unbound group into their copy", %{
      instances: instances,
      world: world,
      group: group
    } do
      {_, instances} = Instance.bind_raid(instances, world, group)
      {:ok, ^world, nil, instances} = admit(instances, 2, 11)
      {:ok, ^world, nil, instances} = admit(instances, 3, 11)
      assert Instance.valid_member?(instances, world, {:party, 11}, actor(3), %Policy{raid?: true})
      assert Instance.saved_worlds(instances, 3) == []
      assert Lockouts.world_for(instances.lockouts, 249, {:party, 11}) == nil
    end
  end

  describe "group_changed/3" do
    test "promoting an unsaved leader releases only the group's permanent binding", %{
      instances: instances,
      world: world,
      group: group
    } do
      {_, instances} = Instance.bind_raid(instances, world, group)
      {dungeon, _, instances} = Instance.enter(instances, 389, {:party, 10}, 1)
      instances = Instance.group_changed(instances, group, %{group | leader: 3})
      assert Lockouts.world_for(instances.lockouts, 249, {:party, 10}) == nil
      assert Instance.saved_worlds(instances, 1) == [world]
      assert Instance.saved_worlds(instances, 2) == [world]
      assert Instance.world_for(instances, 389, {:party, 10}) == dungeon
      {:ok, fresh, nil, _instances} = admit(instances, 3, 10)
      refute fresh == world
    end

    test "promoting a saved leader replaces the group's old save without rebinding players", %{
      instances: instances,
      world: world,
      group: group
    } do
      {_, instances} = Instance.bind_raid(instances, world, group)
      {:ok, other, nil, instances} = admit(instances, 3, 11)
      {_, instances} = Instance.bind_raid(instances, other, %Group{id: 11, leader: 3})
      instances = Instance.group_changed(instances, group, %{group | leader: 3})
      assert Lockouts.world_for(instances.lockouts, 249, {:party, 10}) == other
      assert Instance.saved_worlds(instances, 1) == [world]
      assert {:error, :instance_unavailable} = admit(instances, 1, 10)
      {:ok, ^other, nil, _instances} = admit(instances, 4, 10)
    end

    test "keeps personal saves through disband and shares a leader's save with a new group", %{
      instances: instances,
      world: world,
      group: group
    } do
      {_, instances} = Instance.bind_raid(instances, world, group)
      instances = Instance.group_changed(instances, group, nil)
      assert Instance.saved_worlds(instances, 1) == [world]
      assert Lockouts.world_for(instances.lockouts, 249, {:party, 10}) == nil
      instances = Instance.group_changed(instances, nil, %Group{id: 11, leader: 1})
      assert Lockouts.world_for(instances.lockouts, 249, {:party, 11}) == world
      {:ok, ^world, nil, instances} = admit(instances, 3, 11)
      assert Instance.saved_worlds(instances, 3) == [world]
      assert Instance.saved_worlds(instances, 2) == [world]
    end
  end

  describe "expire_map/2" do
    test "invalidates occupied copies and cannot delete a replacement copy's index", %{
      instances: instances,
      world: world,
      group: group
    } do
      {_, instances} = Instance.bind_raid(instances, world, group)
      instances = Instance.expire_map(instances, 249)
      assert Instance.saved_worlds(instances, 1) == []
      refute Instance.valid_member?(instances, world, {:party, 10}, actor(1), %Policy{raid?: true})

      assert {:error, :instance_unavailable} =
               Instance.admit_copy(instances, actor(1), world, %Policy{raid?: true}, 100)

      assert {[], ^instances} = Instance.bind_raid(instances, world, group)
      {:ok, next, nil, instances} = admit(instances, 1, 10)
      refute next == world
      {instances, ^world} = Instance.leave(instances, 2, world)
      instances = Instance.destroy_empty(instances, world)
      assert Instance.world_for(instances, 249, {:party, 10}) == next
      assert Instance.copy(instances, world) == nil
    end
  end

  defp build_raid(_context) do
    {:ok, world, nil, instances} = admit(%Instance{}, 1, 10)
    {:ok, ^world, nil, instances} = admit(instances, 2, 10)
    %{instances: instances, world: world, group: %Group{id: 10, leader: 1, raid?: true}}
  end

  defp bind(instances, world, group) do
    {saved, instances} = Instance.bind_raid(instances, world, group)
    {Enum.sort(saved), instances}
  end

  defp admit(instances, guid, party, policy \\ %Policy{raid?: true}) do
    Instance.admit(instances, 249, {:party, party}, actor(guid), policy, 0, nil)
  end

  defp actor(guid), do: %Actor{guid: guid, account: guid, raid?: true}
end
