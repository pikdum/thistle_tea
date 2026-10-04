defmodule ThistleTea.Game.Core.InstanceScript.DireMaulTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript
  alias ThistleTea.Game.Core.InstanceScript.DireMaul
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @immol_thar 11_496
  @tortheldrin 11_486
  @highborne_summoner 11_466
  @mana_remnant 11_483
  @zevrim 11_490
  @alzzin 11_492
  @king_gordok 11_501
  @chorush 14_324
  @mizzle 14_353
  @guard_fengus 14_321
  @guard_moldar 14_326

  @force_field 179_503
  @magic_vortex 179_506
  @crumble_wall 177_220
  @corrupt_vine 179_502
  @first_generator 177_259

  setup [:dungeon]

  describe "InstanceScript.scripted_door?/2" do
    test "keeps players' hands off the field, the vortex, and the generators" do
      for door <- [@force_field, @magic_vortex, @crumble_wall, @corrupt_vine, @first_generator] do
        assert InstanceScript.scripted_door?("instance_dire_maul", door)
      end
    end
  end

  describe "the crystal generators" do
    test "Immol'thar is imprisoned until every generator's guards are dead", context do
      assert {:ok, [%Effects.ModifyCreatureUnitFlags{creature_entry: @immol_thar, flags: 0x02000002, mode: :add}], _} =
               Instance.creature_event(context.instances, context.world, spawned(@immol_thar, 1, 84_376))
    end

    test "a generator goes dark once its last guard falls", context do
      [last | others] = DireMaul.generator_guards()[@first_generator]
      instances = Enum.reduce(others, context.instances, &kill_guard(&2, context, &1))

      assert {:ok, [], _} = Instance.game_object_spawned(instances, context.world, @first_generator)

      assert {:ok, [%Effects.OperateGameObject{entry: @first_generator, action: :open}], instances} =
               Instance.creature_event(instances, context.world, guard_death(last))

      assert {:ok, [%Effects.OperateGameObject{entry: @first_generator, action: :open}], _} =
               Instance.game_object_spawned(instances, context.world, @first_generator)

      assert Instance.read(instances, context.world, 1) == {:ok, 0}
    end

    test "the last generator drops the field and frees Immol'thar to his summoners", context do
      {:ok, _, instances} =
        Instance.creature_event(context.instances, context.world, spawned(@highborne_summoner, 7, 300_857))

      {:ok, _, instances} = Instance.creature_event(instances, context.world, spawned(@highborne_summoner, 8, 84_209))

      {last, guards} =
        DireMaul.generator_guards() |> Map.values() |> List.flatten() |> List.pop_at(-1)

      instances = Enum.reduce(guards, instances, &kill_guard(&2, context, &1))
      {:ok, effects, instances} = Instance.creature_event(instances, context.world, guard_death(last))

      assert Instance.read(instances, context.world, 1) == {:ok, 3}
      assert [@force_field, @magic_vortex] -- opened(effects) == []

      assert %Effects.ModifyCreatureUnitFlags{creature_entry: @immol_thar, mode: :remove} =
               Enum.find(effects, &match?(%Effects.ModifyCreatureUnitFlags{}, &1))

      assert %Effects.RunCreatureScript{creature_entry: @highborne_summoner, within: {_hall, 100}, steps: steps} =
               Enum.find(effects, &match?(%Effects.RunCreatureScript{}, &1))

      assert %ScriptStep{command: :set_faction, datalong: 100} = Enum.find(steps, &(&1.command == :set_faction))

      assert %ScriptStep{target_param1: @immol_thar, delay_ms: 1_000} =
               Enum.find(steps, &(&1.command == :attack_start))

      assert %Effects.MonsterTalk{creature_guid: 7, broadcast_text_id: 9_364} =
               Enum.find(effects, &match?(%Effects.MonsterTalk{}, &1))

      assert {:ok, [], _} = Instance.creature_event(instances, context.world, spawned(@immol_thar, 1, 84_376))

      assert {:ok, [%Effects.OperateGameObject{action: :open}], _} =
               Instance.game_object_spawned(instances, context.world, @force_field)
    end

    test "Immol'thar's death opens Prince Tortheldrin to attack", context do
      {:ok, effects, instances} = Instance.creature_event(context.instances, context.world, death(@immol_thar, 1))

      assert Instance.read(instances, context.world, 2) == {:ok, 3}
      assert %Effects.MonsterTalk{creature_entry: @tortheldrin, broadcast_text_id: 9_407} = Enum.at(effects, 0)
      assert %Effects.RunCreatureScript{creature_entry: @tortheldrin, steps: [flags, faction]} = Enum.at(effects, 1)
      assert %ScriptStep{command: :modify_flags, datalong2: 0x100, datalong3: 2} = flags
      assert %ScriptStep{command: :set_faction, datalong: 14} = faction
    end

    test "a Tortheldrin who spawns after Immol'thar fell is already open to attack", context do
      assert {:ok, [], instances} =
               Instance.creature_event(context.instances, context.world, spawned(@tortheldrin, 2, 56_951))

      {:ok, _effects, instances} = Instance.creature_event(instances, context.world, death(@immol_thar, 1))

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: @tortheldrin}], _} =
               Instance.creature_event(instances, context.world, spawned(@tortheldrin, 3, 56_951))
    end
  end

  describe "the east wing" do
    test "Zevrim's death frees Old Ironbark", context do
      {:ok, [], instances} = Instance.creature_event(context.instances, context.world, death(@zevrim, 1))
      assert Instance.read(instances, context.world, 4) == {:ok, 3}
    end

    test "Alzzin breaks the wall when pressed and his death raises the Felvine Shards", context do
      assert {:ok, 4, [%Effects.OperateGameObject{entry: @crumble_wall, action: :open}], instances} =
               Instance.command(context.instances, context.world, 11, 4, :raw)

      {:ok, effects, instances} = Instance.creature_event(instances, context.world, death(@alzzin, 2))

      assert opened(effects) == [@corrupt_vine]
      assert [44_726, 44_727, 44_728, 44_729, 44_730] = for(%Effects.RespawnGameObject{db_guid: g} <- effects, do: g)
      assert {:ok, [], _} = Instance.creature_event(instances, context.world, death(@alzzin, 2))
    end
  end

  describe "the Gordok tribute" do
    test "counts each fallen guard once and freezes the count when the tribute is shown", context do
      assert Instance.read(context.instances, context.world, 15) == {:ok, 6}

      {:ok, [], instances} = Instance.creature_event(context.instances, context.world, death(@guard_fengus, 1))
      {:ok, _, _, instances} = Instance.command(instances, context.world, 6, 4, :raw)
      {:ok, [], instances} = Instance.creature_event(instances, context.world, death(@guard_moldar, 2))

      assert Instance.read(instances, context.world, 15) == {:ok, 4}
      assert Instance.read(instances, context.world, 10) == {:ok, 3}

      assert {:ok, 3, [%Effects.RespawnGameObject{db_guid: 396_409}], instances} =
               Instance.command(instances, context.world, 6, 3, :raw)

      {:ok, [], instances} = Instance.creature_event(instances, context.world, death(@chorush, 3))
      assert Instance.read(instances, context.world, 15) == {:ok, 4}
      assert {:ok, 3, [], _} = Instance.command(instances, context.world, 6, 3, :raw)
    end

    test "the king's death calls Mizzle and stands Cho'Rush down", context do
      {:ok, [mizzle, stand_down], _} = Instance.creature_event(context.instances, context.world, death(@king_gordok, 1))

      assert %Effects.SummonCreature{entry: @mizzle, despawn_type: 7} = mizzle
      assert %Effects.RunCreatureScript{creature_entry: @chorush, steps: [faction, talk]} = stand_down
      assert %ScriptStep{command: :set_faction, datalong: 35} = faction
      assert %ScriptStep{command: :talk, dataint: 9_472, delay_ms: 5_000} = talk
    end

    test "a fallen Cho'Rush is not stood down", context do
      {:ok, _, instances} = Instance.creature_event(context.instances, context.world, death(@chorush, 2))

      assert {:ok, [%Effects.SummonCreature{entry: @mizzle}], _} =
               Instance.creature_event(instances, context.world, death(@king_gordok, 1))
    end
  end

  defp kill_guard(instances, context, db_guid) do
    {:ok, _effects, instances} = Instance.creature_event(instances, context.world, guard_death(db_guid))
    instances
  end

  defp guard_death(db_guid), do: %{death(@mana_remnant, db_guid) | db_guid: db_guid}
  defp spawned(entry, guid, db_guid), do: %{event(entry, guid, :spawned) | db_guid: db_guid}
  defp death(entry, guid), do: event(entry, guid, :death)
  defp event(entry, guid, event), do: %{creature_entry: entry, creature_guid: guid, db_guid: nil, event: event}

  defp opened(effects), do: for(%Effects.OperateGameObject{entry: entry, action: :open} <- effects, do: entry)

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 429, {:player, 100}, 100, "instance_dire_maul")
    %{world: world, instances: instances}
  end
end
