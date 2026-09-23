defmodule ThistleTea.Game.World.System.InstanceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Instance.Admission.Policy
  alias ThistleTea.Game.InstanceScript.Effects.CastPlayerSpell
  alias ThistleTea.Game.InstanceScript.Effects.MonsterTalk
  alias ThistleTea.Game.InstanceScript.Effects.OperateGameObject
  alias ThistleTea.Game.InstanceScript.Effects.SummonCreature
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  describe "admission" do
    test "serializes concurrent entrants without exceeding the copy capacity" do
      name = unique_name()

      start_instance_system(
        name: name,
        owner: fn _ -> {:party, 1} end,
        admission_policy: fn _ -> %Policy{player_limit: 2} end,
        cleanup: fn _ -> :ok end
      )

      guids = Enum.map(1..5, fn _ -> System.unique_integer([:positive]) end)

      results =
        guids
        |> Task.async_stream(fn guid -> {guid, InstanceSystem.enter(389, guid, name)} end, max_concurrency: 5)
        |> Enum.map(fn {:ok, result} -> result end)

      accepted = for {guid, {:ok, world}} <- results, do: {guid, world}
      rejected = for {guid, {:error, :instance_full}} <- results, do: guid
      assert length(accepted) == 2
      assert length(rejected) == 3
      assert InstanceSystem.count(name) == 1
      [{guid, world} | _] = accepted
      assert {:ok, ^world} = InstanceSystem.enter(389, guid, name)
      assert length(hd(InstanceSystem.info(guid, name).copies).members) == 2
      assert Enum.all?(rejected, &(InstanceSystem.info(&1, name).current == nil))
      assert map_size(:sys.get_state(name).instances.entry_history) == 2
    end

    test "resolves the shared account quota from CharacterStore and expires it by the supplied clock" do
      name = unique_name()
      {:ok, clock} = start_supervised({Agent, fn -> 0 end})
      account = System.unique_integer([:positive])
      guids = Enum.map(1..3, fn _ -> System.unique_integer([:positive]) + 10_000_000 end)
      [first, second, other] = guids
      Enum.each([first, second], &CharacterStore.put(%Character{id: &1, account_id: account}))
      CharacterStore.put(%Character{id: other, account_id: account + 1})
      on_exit(fn -> Enum.each(guids, &:ets.delete(CharacterStore, &1)) end)

      start_instance_system(name: name, clock: fn -> Agent.get(clock, & &1) end, cleanup: fn _ -> :ok end)

      for _ <- 1..5 do
        assert {:ok, world} = InstanceSystem.enter(389, first, name)
        InstanceSystem.leave(first, world, name)
        assert {:ok, %{reset: [^world], failed: []}} = InstanceSystem.reset(first, name)
      end

      assert {:error, :too_many_instances} = InstanceSystem.enter(389, second, name)
      assert {:ok, _world} = InstanceSystem.enter(389, other, name)
      Agent.update(clock, fn _ -> 3_600_001 end)
      send(Process.whereis(name), :prune_entry_history)
      assert :sys.get_state(name).instances.entry_history == %{}
      assert {:ok, _world} = InstanceSystem.enter(389, second, name)
    end
  end

  describe "instance lifecycle" do
    test "cleans up an empty copy after its timeout" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_instance_system(name: name, empty_timeout_ms: 1, cleanup: fn world -> send(parent, {:cleaned, world}) end)

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)

      assert_receive {:cleaned, ^world}
      assert InstanceSystem.count(name) == 0
    end

    test "reuses a copy when its owner re-enters before cleanup" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 100,
          cleanup: fn world -> send(parent, {:cleaned, world}) end
        )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)
      assert {:ok, ^world} = InstanceSystem.enter(389, guid, name)

      refute_receive {:cleaned, ^world}, 150
      assert InstanceSystem.count(name) == 1
      assert %Snapshot{status: :no_instance_script} = InstanceData.read(world, [7], table)
    end

    test "resets an empty owned copy immediately" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 10_000,
          cleanup: fn world -> send(parent, {:cleaned, world}) end
        )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)

      assert {:ok, %{reset: [^world], failed: []}} = InstanceSystem.reset(guid, name)
      assert_receive {:cleaned, ^world}
      assert InstanceSystem.count(name) == 0
      assert %Snapshot{status: :missing_copy} = InstanceData.read(world, [7], table)
    end

    test "refuses to reset an occupied copy" do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_instance_system(name: name, cleanup: fn world -> send(parent, {:cleaned, world}) end)

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      assert {:ok, %{reset: [], failed: [^world]}} = InstanceSystem.reset(guid, name)
      refute_receive {:cleaned, ^world}
    end

    test "switches a player into an existing copy" do
      name = unique_name()
      first_guid = System.unique_integer([:positive])
      second_guid = System.unique_integer([:positive])

      start_instance_system(name: name)

      assert {:ok, first_world} = InstanceSystem.enter(389, first_guid, name)
      assert {:ok, second_world} = InstanceSystem.enter(389, second_guid, name)
      assert :ok = InstanceSystem.switch(first_guid, second_world, name)

      assert InstanceSystem.info(first_guid, name).current == second_world
      refute first_world == second_world
    end

    test "stops selecting a former group's copy after membership changes" do
      name = unique_name()
      guid = System.unique_integer([:positive])
      {:ok, owner} = start_supervised({Agent, fn -> {:party, 7} end})

      start_instance_system(
        name: name,
        owner: fn _guid -> Agent.get(owner, & &1) end,
        reset_owner: fn _guid -> {:ok, Agent.get(owner, & &1)} end
      )

      assert {:ok, world} = InstanceSystem.enter(389, guid, name)
      InstanceSystem.leave(guid, world, name)
      Agent.update(owner, fn _owner -> {:player, guid} end)

      assert InstanceSystem.world_for(389, guid, name) == nil
      assert {:error, :instance_unavailable} = InstanceSystem.resume(world, guid, name)
      assert {:ok, next_world} = InstanceSystem.enter(389, guid, name)
      refute next_world == world
    end

    test "captures the map script only when a copy is created" do
      name = unique_name()
      guid = System.unique_integer([:positive])
      {:ok, script_name} = start_supervised({Agent, fn -> "instance_stratholme" end})

      start_instance_system(
        name: name,
        script_name: fn _map_id -> Agent.get(script_name, & &1) end,
        owner: fn _guid -> {:player, guid} end
      )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      InstanceSystem.leave(guid, world, name)
      Agent.update(script_name, fn _name -> nil end)
      assert {:ok, ^world} = InstanceSystem.enter(329, guid, name)

      assert %{script_name: "instance_stratholme"} =
               InstanceSystem.info(guid, name).copies |> Enum.find(&(&1.world == world))
    end

    test "publishes commands after successful transitions and preserves rejected snapshots" do
      name = unique_name()
      guid = System.unique_integer([:positive])
      table = start_instance_system(name: name, script_name: fn 329 -> "instance_stratholme" end)

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(world, [7], table)

      assert {:ok, 2} = InstanceSystem.command(world, 7, 2, :raw, name)
      assert %Snapshot{fields: %{7 => {:ok, 2}}} = InstanceData.read(world, [7], table)

      assert {:error, {:unsupported_field, 9}} = InstanceSystem.command(world, 9, 1, :raw, name)
      assert %Snapshot{fields: %{7 => {:ok, 2}}} = InstanceData.read(world, [7], table)
    end

    test "dispatches exact-copy effects and owns script timers", %{test: test} do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          script_name: fn 329 -> "instance_stratholme" end,
          effect_sink: fn world, effect -> send(parent, {test, world, effect}) end
        )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      assert :ok = InstanceSystem.game_object_used(world, 175_357, name)
      assert %Snapshot{fields: %{0 => {:ok, 1}}} = InstanceData.read(world, [0], table)

      assert_receive {^test, ^world, %SummonCreature{entry: 16_031}}
      assert_receive {^test, ^world, %MonsterTalk{broadcast_text_id: 11_812}}
      assert_receive {^test, ^world, %CastPlayerSpell{spell_id: 27_861}}

      state = :sys.get_state(name)
      assert map_size(state.script_timer_refs) == 5
      {_timer_ref, token} = Map.fetch!(state.script_timer_refs, {world, :baron_run_10_minutes})
      send(Process.whereis(name), {:instance_script_timer, world, :baron_run_10_minutes, token})

      assert_receive {^test, ^world, %MonsterTalk{broadcast_text_id: 11_813}}
      assert_receive {^test, ^world, %CastPlayerSpell{spell_id: 27_863}}

      assert {:ok, 3} = InstanceSystem.command(world, 5, 3, :raw, name)
      state = :sys.get_state(name)
      assert Map.keys(state.script_timer_refs) == [{world, :ysida_reward}]
      assert %Snapshot{fields: %{0 => {:ok, 3}, 5 => {:ok, 3}}} = InstanceData.read(world, [0, 5], table)
    end

    test "reconciles a spawned game object from current script data", %{test: test} do
      parent = self()
      name = unique_name()
      guid = System.unique_integer([:positive])

      start_instance_system(
        name: name,
        script_name: fn 329 -> "instance_stratholme" end,
        effect_sink: fn world, effect -> send(parent, {test, world, effect}) end
      )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      assert {:ok, 3} = InstanceSystem.command(world, 1, 3, :raw, name)
      assert_receive {^test, ^world, %OperateGameObject{entry: 175_380}}

      InstanceSystem.game_object_spawned(world, 175_380, name)
      assert InstanceSystem.count(name) == 1
      assert_receive {^test, ^world, %OperateGameObject{entry: 175_380}}
    end

    test "keeps copy projections isolated and removes timed-out data" do
      name = unique_name()
      first_guid = System.unique_integer([:positive])
      second_guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 1,
          script_name: fn 329 -> "instance_stratholme" end
        )

      assert {:ok, first} = InstanceSystem.enter(329, first_guid, name)
      assert {:ok, second} = InstanceSystem.enter(329, second_guid, name)
      assert {:ok, 1} = InstanceSystem.command(first, 7, 1, :raw, name)

      assert %Snapshot{fields: %{7 => {:ok, 1}}} = InstanceData.read(first, [7], table)
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(second, [7], table)

      InstanceSystem.leave(first_guid, first, name)
      eventually(fn -> assert %Snapshot{status: :missing_copy} = InstanceData.read(first, [7], table) end)
      assert %Snapshot{fields: %{7 => {:ok, 0}}} = InstanceData.read(second, [7], table)
    end

    test "ignores stale cleanup after re-entry" do
      name = unique_name()
      guid = System.unique_integer([:positive])

      table =
        start_instance_system(
          name: name,
          empty_timeout_ms: 50,
          script_name: fn 329 -> "instance_stratholme" end
        )

      assert {:ok, world} = InstanceSystem.enter(329, guid, name)
      assert {:ok, 1} = InstanceSystem.command(world, 7, 1, :raw, name)
      InstanceSystem.leave(guid, world, name)
      assert {:ok, ^world} = InstanceSystem.enter(329, guid, name)

      Process.sleep(75)
      assert %Snapshot{fields: %{7 => {:ok, 1}}} = InstanceData.read(world, [7], table)
    end
  end

  defp start_instance_system(options) do
    table = :ets.new(:instance_system_projection, [:set, :public, read_concurrency: true])
    start_supervised!({InstanceSystem, Keyword.put(options, :projection_table, table)})
    table
  end

  defp eventually(assertion, attempts \\ 20)
  defp eventually(assertion, 0), do: assertion.()

  defp eventually(assertion, attempts) do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(5)
      eventually(assertion, attempts - 1)
  end

  defp unique_name do
    :"instance_system_test_#{System.unique_integer([:positive])}"
  end
end
