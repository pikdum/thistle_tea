defmodule ThistleTea.Game.InstanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.WorldRef

  describe "enter/4" do
    test "gives party members the same copy" do
      {first, nil, instances} = Instance.enter(%Instance{}, 389, {:party, 7}, 100)
      {second, nil, instances} = Instance.enter(instances, 389, {:party, 7}, 200)

      assert first == second
      assert Instance.member_world(instances, 100) == first
      assert Instance.member_world(instances, 200) == first
    end

    test "gives solo owners separate copies" do
      {first, nil, instances} = Instance.enter(%Instance{}, 389, {:player, 100}, 100)
      {second, nil, _instances} = Instance.enter(instances, 389, {:player, 200}, 200)

      refute first == second
    end

    test "returns an emptied previous copy when a member transfers" do
      {first, nil, instances} = Instance.enter(%Instance{}, 389, {:player, 100}, 100)
      {_second, emptied, instances} = Instance.enter(instances, 33, {:player, 100}, 100)

      assert emptied == first
      assert Instance.empty?(instances, first)
    end
  end

  describe "destroy_empty/2" do
    test "retains an empty copy for re-entry until it is destroyed" do
      owner = {:player, 100}
      {world, nil, instances} = Instance.enter(%Instance{}, 389, owner, 100)
      {instances, ^world} = Instance.leave(instances, 100, world)

      assert Instance.world_for(instances, 389, owner) == world

      instances = Instance.destroy_empty(instances, world)
      assert Instance.world_for(instances, 389, owner) == nil
    end
  end

  describe "join_copy/3" do
    test "moves a member into an existing copy" do
      {first, nil, instances} = Instance.enter(%Instance{}, 389, {:player, 100}, 100)
      {second, nil, instances} = Instance.enter(instances, 389, {:player, 200}, 200)

      assert {:ok, ^first, instances} = Instance.join_copy(instances, 100, second)
      assert Instance.empty?(instances, first)
      assert Instance.member_world(instances, 100) == second
    end

    test "rejects an unknown copy" do
      world = WorldRef.instance(389, 99)
      assert Instance.join_copy(%Instance{}, 100, world) == {:error, :not_found}
    end
  end
end
