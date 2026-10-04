defmodule ThistleTea.Game.Core.InstanceScript.MaraudonTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Test.Unique

  @celebras_the_cursed 12_225
  @celebras_the_redeemed 13_716

  setup [:dungeon]

  describe "creature_event/3" do
    test "the redeemed spirit hides until Celebras the Cursed falls", context do
      guid = Unique.integer()
      spawned = %{creature_entry: @celebras_the_redeemed, event: :spawned, creature_guid: guid, db_guid: 55_105}

      assert {:ok, [%Effects.RunCreatureScript{creature_guid: ^guid, steps: [hide]}], instances} =
               Instance.creature_event(context.instances, context.world, spawned)

      assert %ScriptStep{command: :set_concealed, datalong: 1} = hide

      death = %{creature_entry: @celebras_the_cursed, event: :death, creature_guid: Unique.integer(), db_guid: 55_104}

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: @celebras_the_redeemed, steps: [reveal]}], instances} =
               Instance.creature_event(instances, context.world, death)

      assert %ScriptStep{command: :set_concealed, datalong: 0} = reveal
      assert Instance.read(instances, context.world, 1) == {:ok, 3}

      assert {:ok, [], instances} = Instance.creature_event(instances, context.world, death)
      assert {:ok, [], _instances} = Instance.creature_event(instances, context.world, spawned)
    end
  end

  defp dungeon(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 349, {:player, 100}, 100, "instance_maraudon")
    %{world: world, instances: instances}
  end
end
