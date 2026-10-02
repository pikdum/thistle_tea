defmodule ThistleTea.Game.Core.InstanceScript.RazorfenKraulTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @agathelos 4_422
  @ward 21_099

  setup [:dungeon]

  describe "set_data/3" do
    test "the second fallen Ward Keeper drops the ward and frees Agathelos", context do
      assert {:ok, 0, [], instances} = Instance.command(context.instances, context.world, 1, 3, :raw)
      assert {:ok, [], _} = Instance.game_object_spawned(instances, context.world, @ward)

      assert {:ok, 3, [open, release], instances} = Instance.command(instances, context.world, 1, 3, :raw)
      assert open == %Effects.OperateGameObject{entry: @ward, action: :open}
      assert %Effects.RunCreatureScript{creature_entry: @agathelos, steps: steps} = release

      assert [
               %ScriptStep{command: :set_run, datalong: 1},
               %ScriptStep{command: :set_default_movement, datalong: 2}
             ] = steps

      assert {:ok, [^open], _} = Instance.game_object_spawned(instances, context.world, @ward)
      assert {:ok, 3, [], _} = Instance.command(instances, context.world, 1, 3, :raw)
    end
  end

  describe "creature_event/3" do
    test "Agathelos keeps his patrol when he spawns again", context do
      event = %{creature_entry: @agathelos, event: :spawned}
      assert {:ok, [], _} = Instance.creature_event(context.instances, context.world, event)

      {:ok, _stored, _effects, instances} = Instance.command(context.instances, context.world, 1, 3, :raw)
      {:ok, _stored, _effects, instances} = Instance.command(instances, context.world, 1, 3, :raw)

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: @agathelos}], _} =
               Instance.creature_event(instances, context.world, event)
    end
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 47, {:player, 100}, 100, "instance_razorfen_kraul")
    %{world: world, instances: instances}
  end
end
