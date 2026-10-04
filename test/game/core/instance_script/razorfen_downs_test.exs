defmodule ThistleTea.Game.Core.InstanceScript.RazorfenDownsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @gong 148_917
  @tomb_fiend 7_349
  @tomb_reaver 7_351
  @tuten_kash 7_355
  @gong_waves 1

  setup [:dungeon]

  describe "game_object_used/3" do
    test "the gong calls eight Tomb Fiends to it and falls silent", context do
      assert {:ok, [%Effects.OperateGameObject{entry: @gong, action: :inert} | summons], instances} =
               Instance.game_object_used(context.instances, context.world, @gong)

      assert length(summons) == 8
      assert Enum.all?(summons, &match?(%Effects.SummonCreature{entry: @tomb_fiend, despawn_type: 7}, &1))
      assert summons |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 8

      assert Enum.all?(
               summons,
               &match?(%Effects.SummonCreature{steps: [%ScriptStep{command: :move_to, datalong: 3}]}, &1)
             )

      assert Instance.read(instances, context.world, @gong_waves) == {:ok, 1}
    end
  end

  describe "set_data/3" do
    test "the gong wakes once a wave is dead and brings the reavers, then Tuten'kash", context do
      gong = fn instances, expected ->
        {:ok, [%Effects.OperateGameObject{action: :inert} | summons], instances} =
          Instance.game_object_used(instances, context.world, @gong)

        assert Enum.map(summons, & &1.entry) == expected
        instances
      end

      instances = gong.(context.instances, List.duplicate(@tomb_fiend, 8))
      instances = slay(instances, context.world, 7)

      assert {:ok, 9, [%Effects.OperateGameObject{entry: @gong, action: :active}], instances} =
               Instance.command(instances, context.world, @gong_waves, 1, :increment)

      instances = gong.(instances, List.duplicate(@tomb_reaver, 4))
      instances = slay(instances, context.world, 3)

      assert {:ok, 14, [%Effects.OperateGameObject{action: :active}], instances} =
               Instance.command(instances, context.world, @gong_waves, 1, :increment)

      instances = gong.(instances, [@tuten_kash])

      assert {:ok, [%Effects.OperateGameObject{action: :inert}], _instances} =
               Instance.game_object_spawned(instances, context.world, @gong)
    end

    test "putting out the idol's fires removes the oven, mouth, and cup fires", context do
      assert {:ok, 1, effects, _instances} = Instance.command(context.instances, context.world, 2, 1, :raw)
      assert effects |> Enum.map(& &1.db_guid) |> Enum.sort() == [32_027, 32_029, 32_030, 32_031]
      assert Enum.all?(effects, &match?(%Effects.SuspendGameObject{}, &1))
    end
  end

  defp slay(instances, world, count) do
    Enum.reduce(1..count, instances, fn _death, instances ->
      {:ok, _stored, [], instances} = Instance.command(instances, world, @gong_waves, 1, :increment)
      instances
    end)
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 129, {:player, 100}, 100, "instance_razorfen_downs")
    %{world: world, instances: instances}
  end
end
