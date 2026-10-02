defmodule ThistleTea.Game.Core.InstanceScript.ShadowfangKeepTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @courtyard_door 18_895
  @arugals_lair 18_971
  @sorcerers_gate 18_972

  setup [:dungeon]

  describe "set_data/3" do
    test "a freed prisoner opens the Courtyard Door once", context do
      assert {:ok, 3, [effect], instances} = Instance.command(context.instances, context.world, 1, 3, :raw)
      assert effect == open(@courtyard_door)
      assert {:ok, 3, [], _} = Instance.command(instances, context.world, 1, 3, :raw)
    end

    test "the fourth fallen voidwalker opens the Sorcerer's Gate", context do
      {:ok, 0, [], instances} = Instance.command(context.instances, context.world, 6, 1, :raw)

      instances =
        Enum.reduce(1..3, instances, fn slain, instances ->
          assert {:ok, ^slain, [], instances} = Instance.command(instances, context.world, 6, 3, :raw)
          instances
        end)

      assert {:ok, 3, [], instances} = Instance.command(instances, context.world, 6, 2, :raw)
      assert {:ok, 4, [effect], instances} = Instance.command(instances, context.world, 6, 3, :raw)
      assert effect == open(@sorcerers_gate)
      assert {:ok, [^effect], _} = Instance.game_object_spawned(instances, context.world, @sorcerers_gate)
    end

    test "Nandos' death opens Arugal's Lair for good", context do
      {:ok, 1, [], instances} = Instance.command(context.instances, context.world, 4, 1, :raw)
      assert {:ok, 3, [effect], instances} = Instance.command(instances, context.world, 4, 3, :raw)
      assert effect == open(@arugals_lair)

      assert {:ok, 3, [], instances} = Instance.command(instances, context.world, 4, 1, :raw)
      assert {:ok, [^effect], _} = Instance.game_object_spawned(instances, context.world, @arugals_lair)
    end
  end

  describe "game_object_spawned/3" do
    test "the keep's doors stay shut in a fresh copy", context do
      for door <- [@courtyard_door, @arugals_lair, @sorcerers_gate] do
        assert {:ok, [], _} = Instance.game_object_spawned(context.instances, context.world, door)
      end
    end
  end

  defp open(entry), do: %Effects.OperateGameObject{entry: entry, action: :open}

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 33, {:player, 100}, 100, "instance_shadowfang_keep")
    %{world: world, instances: instances}
  end
end
