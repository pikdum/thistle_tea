defmodule ThistleTea.Game.World.InstanceDataTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.InstanceData.Snapshot
  alias ThistleTea.Game.WorldRef

  describe "read/3" do
    test "projects supported defaults and stored values in one batch" do
      table = table()
      world = WorldRef.instance(329, 1)
      copy = %Copy{world: world, owner: {:player, 1}, script_name: "instance_stratholme", data: %{7 => 2}}

      assert :ok = InstanceData.publish(table, copy)

      assert %Snapshot{
               status: :available,
               script_name: "instance_stratholme",
               fields: %{7 => {:ok, 2}, 5 => {:error, {:unsupported_field, 5}}}
             } = InstanceData.read(world, [7, 5, 7], table)
    end

    test "distinguishes no script, unsupported script, missing copy, and open world" do
      table = table()
      no_script = WorldRef.instance(389, 1)
      unsupported = WorldRef.instance(33, 2)

      InstanceData.publish(table, %Copy{world: no_script, owner: {:player, 1}})

      InstanceData.publish(table, %Copy{
        world: unsupported,
        owner: {:player, 2},
        script_name: "instance_shadowfang_keep"
      })

      assert %Snapshot{status: :no_instance_script} = InstanceData.read(no_script, [7], table)

      assert %Snapshot{status: {:unsupported_script, "instance_shadowfang_keep"}} =
               InstanceData.read(unsupported, [7], table)

      assert %Snapshot{status: :missing_copy} = InstanceData.read(WorldRef.instance(329, 99), [7], table)
      assert %Snapshot{status: :open_world} = InstanceData.read(WorldRef.open(329), [7], table)
      assert %Snapshot{status: :open_world} = InstanceData.read_all(WorldRef.open(329), table)
    end

    test "removes a published copy" do
      table = table()
      world = WorldRef.instance(329, 1)
      InstanceData.publish(table, %Copy{world: world, owner: {:player, 1}, script_name: "instance_stratholme"})

      assert :ok = InstanceData.remove(table, world)
      assert %Snapshot{status: :missing_copy} = InstanceData.read(world, [7], table)
    end
  end

  defp table, do: :ets.new(:instance_data_test, [:set, :public, read_concurrency: true])
end
