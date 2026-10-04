defmodule ThistleTea.Game.Core.InstanceScript.GnomereganTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @grubbis_field 0
  @thermaplugg_field 1
  @charge_field 2
  @south_cave_in_field 3
  @north_cave_in_field 4
  @opening_face_field 12

  @emi 7_998
  @grubbis 7_361
  @thermaplugg 7_800
  @walking_bomb 7_915
  @south_cave_in 146_086
  @north_cave_in 146_085
  @final_chamber 142_207
  @third_face 142_209
  @fifth_face 142_213
  @fifth_button 142_218

  setup [:dungeon]

  describe "set_data/3" do
    test "each charge Emi plants appears for an hour and blowing them removes all four", context do
      planted =
        for charge <- 1..4 do
          {:ok, ^charge, [%Effects.RespawnGameObject{db_guid: db_guid, duration_ms: 3_600_000}], _instances} =
            Instance.command(context.instances, context.world, @charge_field, charge, :raw)

          db_guid
        end

      assert planted == [3_997_159, 3_997_160, 3_997_157, 3_997_158]

      assert {:ok, 5, effects, _instances} = Instance.command(context.instances, context.world, @charge_field, 5, :raw)
      assert Enum.sort(Enum.map(effects, & &1.db_guid)) == Enum.sort(planted)
      assert Enum.all?(effects, &match?(%Effects.SuspendGameObject{}, &1))
    end

    test "the cave-ins open and close with their fields", context do
      assert {:ok, 1, [%Effects.OperateGameObject{entry: @south_cave_in, action: :open}], instances} =
               Instance.command(context.instances, context.world, @south_cave_in_field, 1, :raw)

      assert {:ok, 0, [%Effects.OperateGameObject{entry: @south_cave_in, action: :close}], _instances} =
               Instance.command(instances, context.world, @south_cave_in_field, 0, :raw)
    end
  end

  describe "creature_event/3" do
    test "Emi's death fails the event, closing the open cave-in and removing her charges", context do
      {:ok, _stored, _effects, instances} =
        Instance.command(context.instances, context.world, @north_cave_in_field, 1, :raw)

      assert {:ok, effects, instances} = Instance.creature_event(instances, context.world, death(@emi))
      assert [%Effects.OperateGameObject{entry: @north_cave_in, action: :close} | charges] = effects
      assert length(charges) == 4 and Enum.all?(charges, &match?(%Effects.SuspendGameObject{}, &1))
      assert Instance.read(instances, context.world, @grubbis_field) == {:ok, 2}
    end

    test "Grubbis's death ends the event for good and brings back the red rockets", context do
      assert {:ok, effects, instances} = Instance.creature_event(context.instances, context.world, death(@grubbis))
      assert effects |> Enum.map(& &1.db_guid) |> Enum.sort() == [283, 284, 285]
      assert Enum.all?(effects, &match?(%Effects.RespawnGameObject{duration_ms: 3_600_000}, &1))

      assert {:ok, [], instances} = Instance.creature_event(instances, context.world, death(@emi))
      assert Instance.read(instances, context.world, @grubbis_field) == {:ok, 3}
    end

    test "Thermaplugg locks the final chamber and opens the third face when he fights", context do
      assert {:ok, effects, instances} = Instance.creature_event(context.instances, context.world, aggro())

      assert [
               %Effects.OperateGameObject{entry: @final_chamber, action: :lock},
               %Effects.OperateGameObject{entry: @third_face, action: :open},
               %Effects.Schedule{key: {:bomb, 2}, delay_ms: 3_000}
             ] = effects

      assert Instance.read(instances, context.world, @opening_face_field) == {:ok, 1}

      assert {:ok, [%Effects.OperateGameObject{entry: @final_chamber, action: :lock}], _instances} =
               Instance.game_object_spawned(instances, context.world, @final_chamber)

      assert {:ok, [%Effects.OperateGameObject{entry: @third_face, action: :open}], _instances} =
               Instance.game_object_spawned(instances, context.world, @third_face)
    end

    test "giving up unlocks the door, closes every open face, and clears his bombs", context do
      {:ok, _effects, instances} = Instance.creature_event(context.instances, context.world, aggro())
      {:ok, [_bomb, _next], instances} = Instance.timer(instances, context.world, {:bomb, 2})

      assert {:ok, effects, instances} = Instance.creature_event(instances, context.world, event(@thermaplugg, :evade))

      assert [
               %Effects.OperateGameObject{entry: @final_chamber, action: :unlock},
               %Effects.OperateGameObject{entry: @third_face, action: :reset},
               %Effects.CancelSchedules{keys: [{:bomb, 2}]},
               %Effects.RunCreatureScript{creature_entry: @walking_bomb, steps: [%ScriptStep{command: :despawn}]}
             ] = effects

      assert Instance.read(instances, context.world, @thermaplugg_field) == {:ok, 2}
      assert {:ok, [], _instances} = Instance.timer(instances, context.world, {:bomb, 2})
    end
  end

  describe "game_object_used/3" do
    test "a face's button closes it and stops its bombs", context do
      {:ok, _effects, instances} = Instance.creature_event(context.instances, context.world, aggro())

      assert {:ok, 1, [%Effects.OperateGameObject{entry: @fifth_face, action: :open}, %Effects.Schedule{}], instances} =
               Instance.command(instances, context.world, 14, 1, :raw)

      assert {:ok, [%Effects.OperateGameObject{entry: @fifth_face, action: :reset}, cancel], _instances} =
               Instance.game_object_used(instances, context.world, @fifth_button)

      assert cancel == %Effects.CancelSchedules{keys: [{:bomb, 4}]}
    end
  end

  describe "timer/3" do
    test "an open face drops a walking bomb toward Thermaplugg until six are about", context do
      {:ok, _effects, instances} = Instance.creature_event(context.instances, context.world, aggro())

      instances =
        Enum.reduce(1..6, instances, fn _drop, instances ->
          assert {:ok, [bomb, next], instances} = Instance.timer(instances, context.world, {:bomb, 2})
          assert next == %Effects.Schedule{key: {:bomb, 2}, delay_ms: 10_000, max_delay_ms: 25_000}

          assert %Effects.SummonCreature{
                   entry: @walking_bomb,
                   position: {_x, _y, -316.2625, _o},
                   despawn_type: 5,
                   steps: [%ScriptStep{command: :move_to}, %ScriptStep{command: :move_to, datalong: 2} = approach]
                 } = bomb

          assert %ScriptStep{target_type: :nearest_creature_with_entry, target_param1: @thermaplugg} = approach
          instances
        end)

      assert {:ok, [%Effects.Schedule{}], instances} = Instance.timer(instances, context.world, {:bomb, 2})
      {:ok, [], instances} = Instance.creature_event(instances, context.world, death(@walking_bomb))

      assert {:ok, [%Effects.SummonCreature{}, _next], _instances} =
               Instance.timer(instances, context.world, {:bomb, 2})
    end
  end

  defp aggro, do: event(@thermaplugg, :aggro)
  defp death(entry), do: event(entry, :death)
  defp event(entry, event), do: %{creature_entry: entry, creature_guid: 1, event: event}

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 90, {:player, 100}, 100, "instance_gnomeregan")
    %{world: world, instances: instances}
  end
end
