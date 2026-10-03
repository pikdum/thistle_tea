defmodule ThistleTea.Game.Core.InstanceScript.RuinsOfAhnQirajTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Test.Unique

  @kurinnaxx 15_348
  @andorov 15_471

  setup [:raid]

  describe "creature_event/3" do
    test "Kurinnaxx's death loads Andorov's squad once", context do
      death = %{creature_entry: @kurinnaxx, event: :death, creature_guid: Unique.integer(), db_guid: 301_297}

      assert {:ok, [%Effects.LoadCreatureSpawns{db_guids: [301_311, 301_312, 301_313, 301_314, 301_315]}], instances} =
               Instance.creature_event(context.instances, context.world, death)

      assert {:ok, [], _instances} = Instance.creature_event(instances, context.world, death)
    end

    test "Andorov marches along his path as he arrives", context do
      guid = Unique.integer()
      spawned = %{creature_entry: @andorov, event: :spawned, creature_guid: guid, db_guid: 301_311}

      assert {:ok, [%Effects.RunCreatureScript{creature_entry: @andorov, creature_guid: ^guid, steps: steps}], _} =
               Instance.creature_event(context.instances, context.world, spawned)

      assert [%ScriptStep{command: :start_waypoints, datalong: 0, datalong4: 0}] = steps
    end
  end

  defp raid(_context) do
    {world, nil, instances} = Instance.enter(%Instance{}, 509, {:player, 100}, 100, "instance_ruins_of_ahnqiraj")
    %{world: world, instances: instances}
  end
end
