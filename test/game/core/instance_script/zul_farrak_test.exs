defmodule ThistleTea.Game.Core.InstanceScript.ZulFarrakTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.ZulFarrak
  alias ThistleTea.Test.Unique

  @crew [7_604, 7_605, 7_606, 7_607, 7_608]
  @cage 141_072
  @end_door 146_084
  @ukorz 7_267

  setup [:dungeon]

  describe "game_object_used/3" do
    test "opening a cage frees the crew to the top of the stairs once", context do
      assert {:ok, effects, instances} = Instance.game_object_used(context.instances, context.world, @cage)
      assert Instance.read(instances, context.world, 1) == {:ok, 1}
      assert effects |> Enum.map(& &1.creature_entry) |> Enum.sort() == @crew

      weegli = Enum.find(effects, &(&1.creature_entry == 7_607))

      assert [
               %ScriptStep{command: :set_home_position, position: {1_883.87, 1_263.49, 41.55, 4.7}},
               %ScriptStep{command: :move_to, datalong3: 3, datalong4: 2, dataint: 1},
               %ScriptStep{command: :set_faction, datalong: 250}
             ] = weegli.steps

      assert {:ok, [], _} = Instance.game_object_used(instances, context.world, 141_070)
    end
  end

  describe "set_data/3" do
    test "Weegli reaching the stairs gathers the first wave below", context do
      instances = free_crew(context)
      assert {:ok, 3, effects, instances} = Instance.command(instances, context.world, 1, 2, :raw)

      {summons, [schedule]} = Enum.split(effects, -1)
      assert length(summons) == 23

      assert %Effects.SummonCreature{entry: 7_789, position: {1_894.64, 1_206.29, 8.87, +0.0}, despawn_type: 8} =
               hd(summons)

      assert schedule == %Effects.Schedule{key: :send_adds, delay_ms: 1_000}

      assert {:ok, 3, [], _} = Instance.command(instances, context.world, 1, 2, :raw)
    end

    test "blowing the end door opens it for good and draws Ukorz's challenge", context do
      assert {:ok, 3, [open, yell], instances} = Instance.command(context.instances, context.world, 3, 3, :raw)
      assert open == %Effects.OperateGameObject{entry: @end_door, action: :open}
      assert yell == %Effects.MonsterTalk{creature_entry: @ukorz, broadcast_text_id: 6_067}

      assert {:ok, [^open], _} = Instance.game_object_spawned(instances, context.world, @end_door)
      assert {:ok, 3, [], _} = Instance.command(instances, context.world, 3, 0, :raw)
    end
  end

  describe "timer/3" do
    test "sends larger groups up the stairs every ten seconds", context do
      {instances, guids} = start_wave(context, 1)

      assert {:ok, first, instances} = Instance.timer(instances, context.world, :send_adds)
      [g0, g1 | _rest] = guids
      assert [{:climb, ^g0}, {:climb, ^g1}, %Effects.Schedule{key: :send_adds}] = moved(first)

      assert {:ok, second, _} = Instance.timer(instances, context.world, :send_adds)
      assert second |> moved() |> Enum.take(3) == Enum.map(Enum.slice(guids, 2, 3), &climb/1)
      assert %Effects.RunCreatureScript{steps: [%ScriptStep{command: :move_to, datalong3: 5}]} = hd(second)
    end

    test "a slain troll is never sent up", context do
      {instances, [first | rest]} = start_wave(context, 1)
      {:ok, [], instances} = death(instances, context, first)

      assert {:ok, effects, _} = Instance.timer(instances, context.world, :send_adds)
      assert effects |> moved() |> Enum.take(2) == Enum.map(Enum.take(rest, 2), &climb/1)
    end
  end

  describe "creature_event/3" do
    test "each cleared wave brings the next, then the crew settles on the floor", context do
      {instances, guids} = start_wave(context, 1)
      {instances, effects} = kill_all(instances, context, guids)

      assert effects == [
               %Effects.CancelSchedules{keys: [:send_adds]},
               %Effects.Schedule{key: :wave_2, delay_ms: 10_000}
             ]

      assert Instance.read(instances, context.world, 1) == {:ok, 4}

      assert {:ok, wave_2, instances} = Instance.timer(instances, context.world, :wave_2)
      assert length(wave_2) == 25
      assert Instance.read(instances, context.world, 1) == {:ok, 5}

      {instances, guids} = report(instances, context, 2)
      {instances, [cancel | effects]} = kill_all(instances, context, guids)
      assert cancel == %Effects.CancelSchedules{keys: [:send_adds]}
      assert {summons, [%Effects.Schedule{key: :wave_3, delay_ms: 5_000}]} = Enum.split(effects, -1)
      assert summons |> Enum.map(& &1.entry) |> Enum.take(-2) == [7_275, 7_796]
      assert Instance.read(instances, context.world, 1) == {:ok, 6}

      assert {:ok, down, instances} = Instance.timer(instances, context.world, :wave_3)
      assert down |> Enum.map(& &1.creature_entry) |> Enum.sort() == @crew
      assert Instance.read(instances, context.world, 1) == {:ok, 7}

      {instances, guids} = report(instances, context, 3)
      {instances, [%Effects.CancelSchedules{keys: [:wave_3]} | settle]} = kill_all(instances, context, guids)
      assert settle |> Enum.map(& &1.creature_entry) |> Enum.sort() == @crew
      assert Instance.read(instances, context.world, 1) == {:ok, 8}
    end

    test "a wave is not cleared until every troll has reported in", context do
      instances = free_crew(context)
      {:ok, 3, _effects, instances} = Instance.command(instances, context.world, 1, 2, :raw)
      guid = Unique.integer()
      {:ok, [], instances} = spawned(instances, context, 7_789, guid)

      assert {:ok, [], instances} = death(instances, context, guid)
      assert Instance.read(instances, context.world, 1) == {:ok, 3}
    end

    test "database trolls do not join a wave", context do
      {instances, _guids} = start_wave(context, 1)
      event = %{creature_entry: 7_789, creature_guid: Unique.integer(), event: :spawned, db_guid: 12}

      assert {:ok, [], instances} = Instance.creature_event(instances, context.world, event)
      assert {:ok, [], _} = Instance.creature_event(instances, context.world, %{event | event: :death})
    end
  end

  defp moved(effects) do
    Enum.map(effects, fn
      %Effects.RunCreatureScript{creature_guid: guid} -> climb(guid)
      other -> other
    end)
  end

  defp climb(guid), do: {:climb, guid}

  defp start_wave(context, number) do
    instances = free_crew(context)
    {:ok, 3, _effects, instances} = Instance.command(instances, context.world, 1, 2, :raw)
    report(instances, context, number)
  end

  defp report(instances, context, number) do
    number
    |> ZulFarrak.wave()
    |> Enum.reduce({instances, []}, fn {entry, _x, _y}, {instances, guids} ->
      guid = Unique.integer()
      {:ok, [], instances} = spawned(instances, context, entry, guid)
      {instances, guids ++ [guid]}
    end)
  end

  defp kill_all(instances, context, guids) do
    {last, others} = List.pop_at(guids, -1)

    instances =
      Enum.reduce(others, instances, fn guid, instances ->
        {:ok, [], instances} = death(instances, context, guid)
        instances
      end)

    {:ok, effects, instances} = death(instances, context, last)
    {instances, effects}
  end

  defp free_crew(context) do
    {:ok, _effects, instances} = Instance.game_object_used(context.instances, context.world, @cage)
    instances
  end

  defp spawned(instances, context, entry, guid),
    do:
      Instance.creature_event(instances, context.world, %{
        creature_entry: entry,
        creature_guid: guid,
        event: :spawned,
        db_guid: nil
      })

  defp death(instances, context, guid),
    do:
      Instance.creature_event(instances, context.world, %{
        creature_entry: 7_789,
        creature_guid: guid,
        event: :death,
        db_guid: nil
      })

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 209, {:player, 100}, 100, "instance_zulfarrak")
    %{world: world, instances: instances}
  end
end
