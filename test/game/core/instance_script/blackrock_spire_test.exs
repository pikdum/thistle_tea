defmodule ThistleTea.Game.Core.InstanceScript.BlackrockSpireTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @room_event_field 0
  @emberseer_field 1
  @ubrs_door_field 5
  @solakar_field 6
  @drakkisath_field 7

  @emberseer_in 175_244
  @emberseer_out 175_153
  @dragonspine_door 164_725
  @father_flame 175_245
  @rookery_hatcher 10_683
  @rookery_guardian 10_258
  @solakar 10_264

  @rooms %{
    175_197 => [40_259, 40_260],
    175_199 => [40_254, 40_255, 45_834],
    175_195 => [40_251],
    175_200 => [40_262, 40_263],
    175_198 => [40_267, 40_268, 45_833],
    175_196 => [40_270, 45_832],
    175_194 => [40_277, 40_455]
  }

  setup [:dungeon]

  describe "set_data/3" do
    test "the Seal of Ascension lights the braziers two by two, then opens the Dragonspine Door", context do
      assert {:ok, 3, [%Effects.Schedule{key: {:ubrs_door, 1}, delay_ms: 2_000}], instances} =
               Instance.command(context.instances, context.world, @ubrs_door_field, 3, :raw)

      assert {:ok, 3, [], instances} = Instance.command(instances, context.world, @ubrs_door_field, 3, :raw)

      braziers = Enum.with_index([{175_528, 175_529}, {175_530, 175_531}, {175_532, 175_533}], 1)

      instances =
        Enum.reduce(braziers, instances, fn {{left, right}, step}, instances ->
          assert {:ok, [open_left, open_right, next], instances} =
                   Instance.timer(instances, context.world, {:ubrs_door, step})

          assert [open_left, open_right] == [operate(left, :open), operate(right, :open)]
          assert next == %Effects.Schedule{key: {:ubrs_door, step + 1}, delay_ms: 3_000}
          instances
        end)

      assert {:ok, [door], instances} = Instance.timer(instances, context.world, {:ubrs_door, 4})
      assert door == operate(@dragonspine_door, :open)

      assert {:ok, [^door], _instances} = Instance.game_object_spawned(instances, context.world, @dragonspine_door)
    end

    test "Drakkisath's defeat opens the gates behind him", context do
      assert {:ok, 3, effects, _instances} =
               Instance.command(context.instances, context.world, @drakkisath_field, 3, :raw)

      assert effects == [operate(175_946, :open), operate(175_947, :open)]
    end

    test "the Emberseer's defeat keeps his exit open for later arrivals", context do
      {:ok, 3, [], instances} = Instance.command(context.instances, context.world, @emberseer_field, 3, :raw)

      assert {:ok, [door], _instances} = Instance.game_object_spawned(instances, context.world, @emberseer_out)
      assert door == operate(@emberseer_out, :open)
    end
  end

  describe "creature_event/3" do
    test "a rune goes dark once its alcove's guardians are dead", context do
      [first, second] = Map.fetch!(@rooms, 175_197)

      assert {:ok, [], instances} = Instance.creature_event(context.instances, context.world, death(first))
      assert {:ok, [dark], instances} = Instance.creature_event(instances, context.world, death(second))
      assert dark == operate(175_197, :close)

      assert {:ok, [^dark], _instances} = Instance.game_object_spawned(instances, context.world, 175_197)
      assert {:ok, [], _instances} = Instance.game_object_spawned(instances, context.world, 175_199)
    end

    test "every rune dark opens the way to the Emberseer", context do
      {last_rune, [last_guard | _others]} = Enum.at(@rooms, 0)

      instances =
        @rooms
        |> Enum.flat_map(fn {_rune, guards} -> guards end)
        |> Enum.reject(&(&1 == last_guard))
        |> Enum.reduce(context.instances, fn db_guid, instances ->
          {:ok, _effects, instances} = Instance.creature_event(instances, context.world, death(db_guid))
          instances
        end)

      assert {:ok, effects, instances} = Instance.creature_event(instances, context.world, death(last_guard))
      assert effects == [operate(last_rune, :close), operate(@emberseer_in, :open)]
      assert Instance.read(instances, context.world, @room_event_field) == {:ok, 3}
    end

    test "deaths outside the alcoves change nothing", context do
      assert {:ok, [], instances} = Instance.creature_event(context.instances, context.world, death(1))
      assert Instance.read(instances, context.world, @room_event_field) == {:ok, 0}
    end
  end

  describe "game_object_used/3" do
    test "Father Flame starts the rookery, which ends with Solakar Flamewreath", context do
      assert {:ok, [%Effects.Schedule{key: :rookery_wave, delay_ms: 5_000}], instances} =
               Instance.game_object_used(context.instances, context.world, @father_flame)

      assert {:ok, [], instances} = Instance.game_object_used(instances, context.world, @father_flame)

      assert {:ok, [first, second, next], instances} = Instance.timer(instances, context.world, :rookery_wave)
      assert %Effects.SummonCreature{entry: @rookery_hatcher, steps: [%ScriptStep{command: :talk}]} = first
      assert %Effects.SummonCreature{entry: @rookery_hatcher, steps: []} = second
      assert next == %Effects.Schedule{key: :rookery_wave, delay_ms: 30_000, max_delay_ms: 40_000}

      {waves, instances} =
        Enum.map_reduce(1..4, instances, fn _wave, instances ->
          {:ok, [left, right, _next], instances} = Instance.timer(instances, context.world, :rookery_wave)
          {Enum.map([left, right], & &1.entry), instances}
        end)

      assert Enum.all?(List.flatten(waves), &(&1 in [@rookery_hatcher, @rookery_guardian]))
      assert @rookery_guardian in List.flatten(waves)

      assert {:ok, [%Effects.SummonCreature{entry: @solakar}], instances} =
               Instance.timer(instances, context.world, :rookery_wave)

      assert Instance.read(instances, context.world, @solakar_field) == {:ok, 3}
      assert {:ok, [], _instances} = Instance.timer(instances, context.world, :rookery_wave)
    end

    test "Father Flame stays cold once Drakkisath is dead", context do
      {:ok, 3, _effects, instances} = Instance.command(context.instances, context.world, @drakkisath_field, 3, :raw)

      assert {:ok, [], instances} = Instance.game_object_used(instances, context.world, @father_flame)
      assert Instance.read(instances, context.world, @solakar_field) == {:ok, 0}
    end
  end

  defp death(db_guid), do: %{creature_entry: 9_819, creature_guid: 1, db_guid: db_guid, event: :death}

  defp operate(entry, action), do: %Effects.OperateGameObject{entry: entry, action: action}

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 229, {:player, 100}, 100, "instance_blackrock_spire")
    %{world: world, instances: instances}
  end
end
