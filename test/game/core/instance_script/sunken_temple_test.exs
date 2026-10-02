defmodule ThistleTea.Game.Core.InstanceScript.SunkenTempleTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @protectors [5_712, 5_713, 5_714, 5_715, 5_716, 5_717]
  @jammalan 5_710
  @shade_of_eranikus 5_709
  @barrier 149_431

  setup [:dungeon]

  describe "creature_event/3" do
    test "the barrier drops once all six protectors are dead", context do
      [last | others] = Enum.reverse(@protectors)

      instances =
        Enum.reduce(others ++ [hd(others)], context.instances, fn protector, instances ->
          assert {:ok, [], instances} = death(instances, context, protector)
          assert {:ok, 0, [], instances} = Instance.command(instances, context.world, 5, 3, :raw)
          instances
        end)

      assert {:ok, [], _} = Instance.game_object_spawned(instances, context.world, @barrier)

      assert {:ok, [open, yell], instances} = death(instances, context, last)
      assert open == %Effects.OperateGameObject{entry: @barrier, action: :open}
      assert yell == %Effects.MonsterTalk{creature_entry: @jammalan, broadcast_text_id: 4_490}
      assert Instance.read(instances, context.world, 5) == {:ok, 3}
      assert {:ok, [^open], _} = Instance.game_object_spawned(instances, context.world, @barrier)
      assert {:ok, [], _} = death(instances, context, last)
    end

    test "the Shade of Eranikus sleeps out of reach until Jammal'an falls", context do
      spawned = %{creature_entry: @shade_of_eranikus, event: :spawned}
      assert {:ok, [asleep], _} = Instance.creature_event(context.instances, context.world, spawned)
      assert eranikus(asleep) == {1, 3}

      {:ok, 1, [], instances} = Instance.command(context.instances, context.world, 6, 1, :raw)
      assert {:ok, 3, [reachable], instances} = Instance.command(instances, context.world, 6, 3, :raw)
      assert eranikus(reachable) == {2, 3}
      assert {:ok, 3, [], instances} = Instance.command(instances, context.world, 6, 1, :raw)

      assert {:ok, [], _} = Instance.creature_event(instances, context.world, spawned)

      aggro = %{creature_entry: @shade_of_eranikus, event: :aggro}
      assert {:ok, [awake], _} = Instance.creature_event(instances, context.world, aggro)
      assert eranikus(awake) == {2, 0}
    end
  end

  defp eranikus(%Effects.RunCreatureScript{creature_entry: @shade_of_eranikus, steps: steps}) do
    [
      %ScriptStep{command: :modify_flags, datalong: 46, datalong2: 0x100, datalong3: immunity},
      %ScriptStep{command: :stand_state, datalong: stand_state}
    ] = steps

    {immunity, stand_state}
  end

  defp death(instances, context, entry),
    do: Instance.creature_event(instances, context.world, %{creature_entry: entry, event: :death})

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 109, {:player, 100}, 100, "instance_sunken_temple")
    %{world: world, instances: instances}
  end
end
