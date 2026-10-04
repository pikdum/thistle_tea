defmodule ThistleTea.Game.Core.InstanceScript.MoltenCoreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects, as: CoreEffects
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @majordomo 8
  @ragnaros 9
  @lieutenants [12_098, 12_056, 12_264, 11_988, 12_057, 11_982, 12_259]
  @runes [176_951, 176_952, 176_953, 176_954, 176_955, 176_956, 176_957]
  @sulfuron_rune 176_951
  @sulfuron_circle 43_157
  @sulfuron_circle_entry 178_187

  setup [:raid]

  describe "game_object_used/3" do
    test "a rune stays lit until its lieutenant is dead", context do
      assert {:ok, [], instances} = Instance.game_object_used(context.instances, context.world, @sulfuron_rune)

      {:ok, _effects, instances} = Instance.creature_event(instances, context.world, creature(12_098, :death))

      assert {:ok, [douse], instances} = Instance.game_object_used(instances, context.world, @sulfuron_rune)
      assert douse == %Effects.SuspendGameObject{db_guid: @sulfuron_circle}
      assert Instance.copy(instances, context.world).data[16] == 3
    end

    test "Majordomo arrives once, when the last rune goes out", context do
      instances = kill_all(context.instances, context.world, @lieutenants)
      {first, [last]} = Enum.split(@runes, 6)
      instances = douse_all(instances, context.world, first)

      assert {:ok, [_douse, summon], instances} = Instance.game_object_used(instances, context.world, last)
      assert %Effects.SummonCreature{entry: 12_018, position: {758.089, _, _, _}, despawn_type: 6} = summon

      assert {:ok, [_douse], _instances} = Instance.game_object_used(instances, context.world, last)
    end
  end

  describe "game_object_spawned/3" do
    test "a doused rune's circle of fire stays out", context do
      assert {:ok, [], _} = Instance.game_object_spawned(context.instances, context.world, @sulfuron_circle_entry)

      instances = kill_all(context.instances, context.world, [12_098])
      instances = douse_all(instances, context.world, [@sulfuron_rune])

      assert {:ok, [suspend], _} = Instance.game_object_spawned(instances, context.world, @sulfuron_circle_entry)
      assert suspend == %Effects.SuspendGameObject{db_guid: @sulfuron_circle}
    end
  end

  describe "creature_event/3" do
    test "a dead lieutenant's guard does not come back", context do
      guard = creature(11_672, :spawned)
      assert {:ok, [], instances} = Instance.creature_event(context.instances, context.world, guard)

      instances = kill_all(instances, context.world, [11_988])

      assert {:ok, [%Effects.RunCreatureScript{creature_guid: 1, steps: [%ScriptStep{command: :despawn}]}], _} =
               Instance.creature_event(instances, context.world, guard)
    end

    test "Ragnaros roars seven seconds after Majordomo burns, then turns on the raid", context do
      assert {:ok, [%Effects.Schedule{key: :ragnaros_roars, delay_ms: 7_000}], instances} =
               Instance.creature_event(context.instances, context.world, creature(12_018, :death))

      assert {:ok, [talk, roar, engage_later], instances} = Instance.timer(instances, context.world, :ragnaros_roars)
      assert %Effects.MonsterTalk{creature_entry: 11_502, broadcast_text_id: 7_685} = talk

      assert %Effects.RunCreatureScript{creature_entry: 11_502, steps: [%ScriptStep{command: :emote, datalong: 15}]} =
               roar

      assert %Effects.Schedule{key: :ragnaros_engages, delay_ms: 3_000} = engage_later

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: 11_502, steps: [immunity, pulse]}], _} =
               Instance.timer(instances, context.world, :ragnaros_engages)

      assert %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x100, datalong3: 2} = immunity
      assert %ScriptStep{command: :zone_combat_pulse} = pulse
    end

    test "Ragnaros's death settles the raid", context do
      instances = kill_all(context.instances, context.world, [11_502])
      assert Instance.copy(instances, context.world).data[@ragnaros] == 3
    end
  end

  describe "command/5" do
    test "Majordomo's defeat brings out the Cache of the Firelord once", context do
      assert {:ok, 3, [cache], instances} = Instance.command(context.instances, context.world, @majordomo, 3, :raw)
      assert cache == %Effects.RespawnGameObject{db_guid: 362_148, duration_ms: 3_600_000}

      assert {:ok, 3, [], _} = Instance.command(instances, context.world, @majordomo, 3, :raw)
    end
  end

  defp kill_all(instances, world, entries) do
    Enum.reduce(entries, instances, fn entry, instances ->
      {:ok, _effects, instances} = Instance.creature_event(instances, world, creature(entry, :death))
      instances
    end)
  end

  defp douse_all(instances, world, runes) do
    Enum.reduce(runes, instances, fn rune, instances ->
      {:ok, _effects, instances} = Instance.game_object_used(instances, world, rune)
      instances
    end)
  end

  defp creature(entry, event) do
    %CoreEffects.InstanceCreatureEvent{world: nil, creature_guid: 1, creature_entry: entry, event: event, db_guid: 1}
  end

  defp raid(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 409, {:player, 100}, 100, "instance_molten_core")
    %{world: world, instances: instances}
  end
end
