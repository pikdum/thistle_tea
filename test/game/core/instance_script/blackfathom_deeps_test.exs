defmodule ThistleTea.Game.Core.InstanceScript.BlackfathomDeepsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects, as: CoreEffects
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @kelris 10
  @shrine 11
  @portal 21_117
  @fires [21_118, 21_119, 21_120, 21_121]
  @servants [4_825, 4_978, 4_815, 4_977]

  setup [:dungeon]

  describe "game_object_used/3" do
    test "a fire lit while Kelris lives flickers out", context do
      [fire | _] = @fires
      assert {:ok, [schedule], instances} = Instance.game_object_used(context.instances, context.world, fire)
      assert schedule == %Effects.Schedule{key: {:fire_reset, fire}, delay_ms: 1_000}

      assert {:ok, [reset], _} = Instance.timer(instances, context.world, {:fire_reset, fire})
      assert reset == %Effects.OperateGameObject{entry: fire, action: :reset}
    end

    test "each fire lit after Kelris falls calls the next wave", context do
      instances = slay_kelris(context)

      {instances, keys} =
        Enum.reduce(@fires, {instances, []}, fn fire, {instances, keys} ->
          assert {:ok, [%Effects.Schedule{key: key, delay_ms: 3_000}], instances} =
                   Instance.game_object_used(instances, context.world, fire)

          {instances, keys ++ [key]}
        end)

      assert keys == [{:wave, 0}, {:wave, 1}, {:wave, 2}, {:wave, 3}]
      assert Instance.copy(instances, context.world).data[@shrine] == 1
      assert {:ok, [], _} = Instance.game_object_used(instances, context.world, hd(@fires))
    end
  end

  describe "timer/3" do
    test "the waves summon Aku'mai's servants into the shrine", context do
      instances = light_all(slay_kelris(context), context.world)

      counts =
        for wave <- 0..3 do
          assert {:ok, summons, _} = Instance.timer(instances, context.world, {:wave, wave})
          assert Enum.all?(summons, &(&1.despawn_type == 7 and &1.entry in @servants))
          length(summons)
        end

      assert counts == [4, 2, 4, 8]
    end
  end

  describe "creature_event/3" do
    test "the portal opens once every called servant has died", context do
      instances = light_all(slay_kelris(context), context.world)

      {instances, summons} =
        Enum.reduce(0..3, {instances, []}, fn wave, {instances, summons} ->
          {:ok, wave_summons, instances} = Instance.timer(instances, context.world, {:wave, wave})
          {instances, summons ++ wave_summons}
        end)

      {last, rest} = List.pop_at(summons, -1)

      instances =
        Enum.reduce(rest, instances, fn summon, instances ->
          assert {:ok, [], instances} = Instance.creature_event(instances, context.world, death(summon.entry))
          instances
        end)

      assert {:ok, [open], instances} = Instance.creature_event(instances, context.world, death(last.entry))
      assert open == %Effects.OperateGameObject{entry: @portal, action: :open}
      assert {:ok, [^open], _} = Instance.game_object_spawned(instances, context.world, @portal)
    end

    test "the dungeon's own spawns do not count toward the shrine", context do
      instances = light_all(slay_kelris(context), context.world)
      {:ok, _summons, instances} = Instance.timer(instances, context.world, {:wave, 0})
      event = %{death(4_825) | db_guid: 32_000}
      assert {:ok, [], instances} = Instance.creature_event(instances, context.world, event)
      assert Instance.copy(instances, context.world).script_state.remaining == 4
    end
  end

  describe "game_object_spawned/3" do
    test "the portal stays shut in a fresh copy", context do
      assert {:ok, [], _} = Instance.game_object_spawned(context.instances, context.world, @portal)
    end
  end

  defp slay_kelris(context) do
    {:ok, 3, [], instances} = Instance.command(context.instances, context.world, @kelris, 3, :raw)
    instances
  end

  defp light_all(instances, world) do
    Enum.reduce(@fires, instances, fn fire, instances ->
      {:ok, _effects, instances} = Instance.game_object_used(instances, world, fire)
      instances
    end)
  end

  defp death(entry) do
    %CoreEffects.InstanceCreatureEvent{
      world: nil,
      creature_guid: 1,
      creature_entry: entry,
      event: :death,
      db_guid: nil
    }
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 48, {:player, 100}, 100, "instance_blackfathom_deeps")
    %{world: world, instances: instances}
  end
end
