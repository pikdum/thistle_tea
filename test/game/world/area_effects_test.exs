defmodule ThistleTea.Game.World.AreaEffectsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.AreaEffects

  describe "register/2" do
    test "tracks the registering process by caster and spell" do
      caster_guid = unique_guid()

      assert {:ok, _owner} = AreaEffects.register(caster_guid, 10)
      assert AreaEffects.pids(caster_guid, 10) == [self()]
      assert AreaEffects.pids(caster_guid, 11) == []
      assert AreaEffects.pids(unique_guid(), 10) == []
    end

    test "rejects invalid keys" do
      assert AreaEffects.register(nil, 10) == {:error, :invalid_key}
    end
  end

  describe "pids/2" do
    test "returns every process registered under the same key" do
      caster_guid = unique_guid()
      parent = self()

      task =
        Task.async(fn ->
          AreaEffects.register(caster_guid, 10)
          send(parent, :registered)

          receive do
            :done -> :ok
          end
        end)

      assert_receive :registered
      AreaEffects.register(caster_guid, 10)

      assert Enum.sort(AreaEffects.pids(caster_guid, 10)) == Enum.sort([self(), task.pid])

      send(task.pid, :done)
      Task.await(task)
    end
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
