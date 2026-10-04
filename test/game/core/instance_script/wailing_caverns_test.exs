defmodule ThistleTea.Game.Core.InstanceScript.WailingCavernsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @anacondra 3_671
  @serpentis 3_673
  @disciple 3_678
  @druid_of_the_fang 3_840
  @mutanus_field 5
  @disciple_field 4
  @done 3
  @special 4

  setup [:dungeon]

  describe "set_data/3" do
    test "Lord Serpentis cries out once, when the first of the other Fanglords falls", context do
      assert {:ok, @done, [%Effects.MonsterTalk{creature_entry: @serpentis, broadcast_text_id: 2_102}], instances} =
               Instance.command(context.instances, context.world, 0, @done, :raw)

      assert {:ok, @done, [], _instances} = Instance.command(instances, context.world, 1, @done, :raw)
    end

    test "the disciple calls the party once all four Fanglords lie dead", context do
      instances =
        Enum.reduce([0, 1, 3], context.instances, fn field, instances ->
          {:ok, @done, _effects, instances} = Instance.command(instances, context.world, field, @done, :raw)
          instances
        end)

      assert Instance.read(instances, context.world, @disciple_field) == {:ok, 0}

      assert {:ok, @done, [%Effects.MonsterTalk{creature_entry: @disciple, broadcast_text_id: 2_101}], instances} =
               Instance.command(instances, context.world, 2, @done, :raw)

      assert Instance.read(instances, context.world, @disciple_field) == {:ok, @special}
    end

    test "a resting Lady Anacondra dismisses the Druid of the Fang beside her", context do
      assert {:ok, @special, [%Effects.RunCreatureScript{creature_entry: @anacondra, steps: [despawn]}], _instances} =
               Instance.command(context.instances, context.world, 0, @special, :raw)

      assert %ScriptStep{
               command: :despawn,
               target_type: :nearest_creature_with_entry,
               target_param1: @druid_of_the_fang
             } = despawn
    end

    test "the nightmare's creatures vanish when Mutanus dies, sparing Kresh and the druids", context do
      assert {:ok, @done, effects, _instances} =
               Instance.command(context.instances, context.world, @mutanus_field, @done, :raw)

      entries = Enum.map(effects, & &1.creature_entry)
      assert @anacondra in entries
      assert @druid_of_the_fang in entries
      refute Enum.any?([3_653, @disciple, 3_679], &(&1 in entries))
      assert Enum.all?(effects, &match?(%Effects.RunCreatureScript{steps: [%ScriptStep{command: :despawn}]}, &1))
    end
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 43, {:player, 100}, 100, "instance_wailing_caverns")
    %{world: world, instances: instances}
  end
end
