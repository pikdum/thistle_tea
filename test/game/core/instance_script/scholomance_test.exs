defmodule ThistleTea.Game.Core.InstanceScript.ScholomanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects, as: CoreEffects
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @gandling 0
  @kirtonos 7
  @viewing_room_door 14
  @room_bosses [11_261, 10_505, 10_502, 10_504, 10_901, 10_507]
  @room_gates [177_371, 177_372, 177_373, 177_375, 177_376, 177_377]
  @kirtonos_gate 175_570
  @brazier 175_564
  @viewing_room 175_167

  setup [:dungeon]

  describe "creature_event/3" do
    test "Darkmaster Gandling appears once all six room bosses are dead", context do
      {five, [last]} = Enum.split(@room_bosses, 5)
      instances = kill_all(context, five)
      assert Map.get(Instance.copy(instances, context.world).data, @gandling, 0) == 0

      assert {:ok, [summon], instances} = Instance.creature_event(instances, context.world, death(last))
      assert %Effects.SummonCreature{entry: 1_853, despawn_type: 7, position: {180.771, _, _, _}} = summon
      assert Instance.copy(instances, context.world).data[@gandling] == 1

      assert {:ok, [], _} = Instance.creature_event(instances, context.world, death(last))
    end

    test "Kirtonos' death reopens the gate and settles the brazier", context do
      {:ok, _effects, instances} = Instance.game_object_used(context.instances, context.world, @brazier)

      assert {:ok, [open], instances} = Instance.creature_event(instances, context.world, death(10_506))
      assert open == operate(@kirtonos_gate, :open)
      assert {:ok, [], _} = Instance.game_object_used(instances, context.world, @brazier)
    end
  end

  describe "command/5" do
    test "Gandling's failure or death opens the room gates", context do
      instances = kill_all(context, @room_bosses)

      assert {:ok, 2, effects, instances} = Instance.command(instances, context.world, @gandling, 2, :raw)
      assert effects == Enum.map(@room_gates, &operate(&1, :open))

      assert {:ok, 3, [], instances} = Instance.command(instances, context.world, @gandling, 3, :raw)
      assert {:ok, [open], _} = Instance.game_object_spawned(instances, context.world, hd(@room_gates))
      assert open == operate(hd(@room_gates), :open)
    end

    test "Kirtonos evading reopens the gate and resets the brazier", context do
      {:ok, _effects, instances} = Instance.game_object_used(context.instances, context.world, @brazier)

      assert {:ok, 2, effects, instances} = Instance.command(instances, context.world, @kirtonos, 2, :raw)
      assert effects == [operate(@kirtonos_gate, :open), operate(@brazier, :reset)]

      assert {:ok, [_close, %Effects.SummonCreature{}], _} =
               Instance.game_object_used(instances, context.world, @brazier)
    end
  end

  describe "game_object_used/3" do
    test "the Brazier of the Herald shuts the gate and calls Kirtonos", context do
      assert {:ok, [close, summon], instances} = Instance.game_object_used(context.instances, context.world, @brazier)
      assert close == operate(@kirtonos_gate, :close)
      assert %Effects.SummonCreature{entry: 10_506, position: {315.028, _, _, _}} = summon
      assert Instance.copy(instances, context.world).data[@kirtonos] == 1
      assert {:ok, [], _} = Instance.game_object_used(instances, context.world, @brazier)
    end

    test "the viewing room door stays open once unlocked", context do
      assert {:ok, [open], instances} = Instance.game_object_used(context.instances, context.world, @viewing_room)
      assert open == operate(@viewing_room, :open)
      assert Instance.copy(instances, context.world).data[@viewing_room_door] == 3
      assert {:ok, [^open], _} = Instance.game_object_spawned(instances, context.world, @viewing_room)
    end
  end

  describe "scripted_door?/2" do
    test "the gates are scripted but the viewing room door stays usable" do
      assert InstanceScript.scripted_door?("instance_scholomance", @kirtonos_gate)
      assert Enum.all?(@room_gates, &InstanceScript.scripted_door?("instance_scholomance", &1))
      refute InstanceScript.scripted_door?("instance_scholomance", @viewing_room)
    end
  end

  defp kill_all(context, entries) do
    Enum.reduce(entries, context.instances, fn entry, instances ->
      {:ok, _effects, instances} = Instance.creature_event(instances, context.world, death(entry))
      instances
    end)
  end

  defp operate(entry, action), do: %Effects.OperateGameObject{entry: entry, action: action}

  defp death(entry) do
    %CoreEffects.InstanceCreatureEvent{
      world: nil,
      creature_guid: 1,
      creature_entry: entry,
      event: :death,
      db_guid: 40_000
    }
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 289, {:player, 100}, 100, "instance_scholomance")
    %{world: world, instances: instances}
  end
end
