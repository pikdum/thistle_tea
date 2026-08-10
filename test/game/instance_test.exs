defmodule ThistleTea.Game.InstanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.WorldRef

  @stratholme "instance_stratholme"

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

    test "keeps a player's copy binding when party membership changes" do
      {world, nil, instances} = Instance.enter(%Instance{}, 389, {:party, 7}, 100)
      {instances, ^world} = Instance.leave(instances, 100, world)
      {reentered, nil, instances} = Instance.enter(instances, 389, {:player, 100}, 100)

      assert reentered == world
      assert Instance.world_for_guid(instances, 389, 100) == world
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
      assert Instance.world_for_guid(instances, 389, 100) == nil
    end
  end

  describe "script data" do
    test "registered unwritten fields read as zero" do
      {world, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)

      assert Instance.read(instances, world, 7) == {:ok, 0}
      assert Instance.read_many(instances, world, [7, 7]) == %{7 => {:ok, 0}}
    end

    test "applies raw, increment, and saturating decrement updates" do
      {world, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)

      assert {:ok, 5, [], instances} = Instance.command(instances, world, 7, 5, :raw)
      assert {:ok, 8, [], instances} = Instance.command(instances, world, 7, 3, :increment)
      assert {:ok, 6, [], instances} = Instance.command(instances, world, 7, 2, :decrement)
      assert {:ok, 0, [], instances} = Instance.command(instances, world, 7, 20, :decrement)
      assert Instance.read(instances, world, 7) == {:ok, 0}
    end

    test "normalizes raw and increment updates as unsigned 32-bit values" do
      {world, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)

      assert {:ok, 1, [], instances} = Instance.command(instances, world, 7, 0x1_0000_0001, :raw)
      assert {:ok, 0, [], instances} = Instance.command(instances, world, 7, 0xFFFF_FFFF, :increment)
      assert Instance.read(instances, world, 7) == {:ok, 0}
    end

    test "isolates data between copies and retains it through re-entry" do
      {first, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)
      {second, nil, instances} = Instance.enter(instances, 329, {:player, 200}, 200, @stratholme)
      {:ok, 2, [], instances} = Instance.command(instances, first, 7, 2, :raw)
      {instances, ^first} = Instance.leave(instances, 100, first)
      {reentered, nil, instances} = Instance.enter(instances, 329, {:player, 100}, 100, nil)

      assert reentered == first
      assert Instance.read(instances, first, 7) == {:ok, 2}
      assert Instance.read(instances, second, 7) == {:ok, 0}
      assert Instance.copy(instances, first).script_name == @stratholme
    end

    test "rejects unsupported and invalid commands without mutation" do
      {supported, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)
      {unsupported, nil, instances} = Instance.enter(instances, 33, {:player, 200}, 200, "instance_shadowfang_keep")
      {no_script, nil, instances} = Instance.enter(instances, 389, {:player, 300}, 300)

      failures = [
        {supported, 9, 1, :raw, {:unsupported_field, 9}},
        {unsupported, 7, 1, :raw, {:unsupported_script, "instance_shadowfang_keep"}},
        {no_script, 7, 1, :raw, :no_instance_script},
        {WorldRef.instance(329, 999), 7, 1, :raw, :missing_copy},
        {WorldRef.open(329), 7, 1, :raw, :open_world},
        {supported, -1, 1, :raw, {:invalid_field, -1}},
        {supported, 7, -1, :raw, {:invalid_value, -1}},
        {supported, 7, 1, :invalid, {:invalid_mode, :invalid}}
      ]

      Enum.each(failures, fn {world, field, value, mode, reason} ->
        assert Instance.command(instances, world, field, value, mode) == {:error, reason}
      end)

      assert Instance.read(instances, supported, 7) == {:ok, 0}
    end

    test "destroying an empty copy removes its data" do
      {world, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, @stratholme)
      {:ok, 2, [], instances} = Instance.command(instances, world, 7, 2, :raw)
      {instances, ^world} = Instance.leave(instances, 100, world)
      instances = Instance.destroy_empty(instances, world)

      assert Instance.read(instances, world, 7) == {:error, :missing_copy}
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
