defmodule ThistleTea.Game.Instance.AdmissionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance
  alias ThistleTea.Game.Instance.Admission
  alias ThistleTea.Game.Instance.Admission.Actor
  alias ThistleTea.Game.Instance.Admission.Policy
  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.WorldRef

  setup [:build_admission]

  describe "check/5" do
    test "requires a raid group only for raids", %{actor: actor, copy: copy} do
      assert Admission.check(%{}, %Policy{}, actor, copy, 0) == :ok
      assert Admission.check(%{}, %Policy{raid?: true}, actor, copy, 0) == {:error, :raid_group_required}
      assert Admission.check(%{}, %Policy{raid?: true}, %{actor | raid?: true}, copy, 0) == :ok
    end

    test "enforces capacity while allowing the current member to remain", %{actor: actor, copy: copy} do
      copy = %{copy | members: MapSet.new([2, 3])}
      assert Admission.check(%{}, %Policy{player_limit: 2}, actor, copy, 0) == {:error, :instance_full}
      assert Admission.check(%{}, %Policy{player_limit: 3}, actor, copy, 0) == :ok
      assert Admission.check(%{}, %Policy{player_limit: 2}, %{actor | guid: 2}, copy, 0) == :ok
    end

    test "shares five distinct copies per hour across characters and maps", %{actor: actor, copy: copy} do
      history = Enum.reduce(1..5, %{}, &Admission.record(&2, actor, WorldRef.instance(30 + &1, &1), 0))
      assert Admission.check(history, %Policy{}, actor, copy, 0) == {:error, :too_many_instances}
      assert Admission.check(history, %Policy{}, %{actor | guid: 2}, copy, 0) == {:error, :too_many_instances}
      assert Admission.check(history, %Policy{}, %{actor | account: 2}, copy, 0) == :ok
      assert Admission.check(history, %Policy{}, actor, %{copy | world: WorldRef.instance(31, 1)}, 0) == :ok
      assert Admission.check(history, %Policy{}, actor, copy, 3_600_000) == {:error, :too_many_instances}
      assert Admission.check(history, %Policy{}, actor, copy, 3_600_001) == :ok
    end

    test "re-entry refreshes only that copy's rolling timestamp", %{actor: actor, copy: copy} do
      history = Enum.reduce(1..5, %{}, &Admission.record(&2, actor, WorldRef.instance(33, &1), &1 * 100))
      history = Admission.record(history, actor, WorldRef.instance(33, 1), 1_000)
      assert Admission.check(history, %Policy{}, actor, copy, 3_600_101) == {:error, :too_many_instances}
      assert Admission.check(history, %Policy{}, actor, copy, 3_600_201) == :ok
      assert map_size(history[actor.account]) == 5
    end
  end

  describe "Instance.admit/7" do
    test "denials preserve membership, bindings, copy allocation, and history", %{actor: actor} do
      policy = %Policy{player_limit: 1}
      {:ok, previous, _, instances} = Instance.admit(%Instance{}, 33, {:player, 1}, actor, policy, 0, nil)
      {:ok, full, _, instances} = Instance.admit(instances, 36, {:party, 1}, %{actor | guid: 2}, policy, 0, nil)

      assert Instance.admit(instances, 36, {:party, 1}, actor, policy, 1, nil) == {:error, :instance_full}
      assert Instance.admit_copy(instances, actor, full, policy, 1) == {:error, :instance_full}
      assert Instance.member_world(instances, actor.guid) == previous
      assert Instance.world_for_guid(instances, 36, actor.guid) == nil
      assert instances.next_id == 3
      assert map_size(instances.entry_history[actor.account]) == 2

      assert Instance.admit(instances, 309, {:player, 1}, actor, %Policy{raid?: true}, 1, nil) ==
               {:error, :raid_group_required}
    end

    test "resetting copies and disconnecting never clears the account quota", %{actor: actor} do
      instances =
        Enum.reduce(1..5, %Instance{}, fn _, instances ->
          {:ok, world, _, instances} = Instance.admit(instances, 33, {:player, 1}, actor, %Policy{}, 0, nil)
          {instances, ^world} = Instance.leave(instances, actor.guid, world)
          Instance.destroy_empty(instances, world)
        end)

      assert instances.copies == %{}
      assert Instance.admit(instances, 33, {:player, 1}, actor, %Policy{}, 1, nil) == {:error, :too_many_instances}
      assert {:ok, _, _, _} = Instance.admit(instances, 33, {:player, 1}, actor, %Policy{}, 3_600_001, nil)
      assert Instance.prune_entry_history(instances, 3_600_001).entry_history == %{}
    end
  end

  defp build_admission(_context) do
    %{actor: %Actor{guid: 1, account: 1}, copy: %Copy{world: WorldRef.instance(33, 6)}}
  end
end
