defmodule ThistleTea.Game.World.BattlegroundSpawnsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Battleground.Spawns
  alias ThistleTea.Game.WorldRef

  defmodule Catalog do
    @moduledoc false

    def event_members(529, 0) do
      [
        %{event1: 0, event2: 0, kind: :game_object, db_guid: 1},
        %{event1: 0, event2: 1, kind: :game_object, db_guid: 2},
        %{event1: 0, event2: 2, kind: :game_object, db_guid: 2},
        %{event1: 0, event2: 3, kind: :creature, db_guid: 3},
        %{event1: 0, event2: 4, kind: :creature, db_guid: 4}
      ]
    end

    def bindings(529, kind, guid), do: Enum.filter(event_members(529, 0), &(&1.kind == kind and &1.db_guid == guid))
  end

  defmodule Pool do
    @moduledoc false
    def resume(world, member), do: send(self(), {:resume, world, member})
    def suspend_spawn(world, member), do: send(self(), {:suspend, world, member})
  end

  setup [:world_copy]

  describe "set_event/5" do
    test "switches all members once and keeps a shared aura eligible in either contested state", %{world: world} do
      assert Spawns.allowed?(world, {:game_object, 1}, Catalog)
      refute Spawns.allowed?(world, {:game_object, 2}, Catalog)
      refute Spawns.allowed?(world, {:creature, 3}, Catalog)
      assert Spawns.allowed?(world, {:game_object, 99}, Catalog)

      Spawns.set_event(world, 0, 1, Catalog, Pool)
      assert_receive {:suspend, ^world, {:game_object, 1}}
      assert_receive {:resume, ^world, {:game_object, 2}}
      refute_receive {:suspend, ^world, {:game_object, 2}}, 0
      refute_receive {:resume, ^world, {:game_object, 2}}, 0
      assert_receive {:suspend, ^world, {:creature, 3}}
      assert_receive {:suspend, ^world, {:creature, 4}}

      Spawns.set_event(world, 0, 2, Catalog, Pool)
      assert Spawns.allowed?(world, {:game_object, 2}, Catalog)
      refute Spawns.allowed?(world, {:game_object, 1}, Catalog)
      Spawns.set_event(world, 0, 3, Catalog, Pool)
      assert Spawns.allowed?(world, {:creature, 3}, Catalog)
      refute Spawns.allowed?(world, {:creature, 4}, Catalog)
      refute Spawns.allowed?(world, {:game_object, 2}, Catalog)
    end

    test "keeps copies independent and disables bindings during replacement and after teardown", %{world: world} do
      other = WorldRef.instance(529, System.unique_integer([:positive]))
      Spawns.open(other)
      on_exit(fn -> Spawns.close(other) end)
      Spawns.set_event(world, 0, nil, Catalog, Pool)
      refute Spawns.allowed?(world, {:game_object, 1}, Catalog)
      assert Spawns.allowed?(other, {:game_object, 1}, Catalog)
      Spawns.set_event(world, 0, 4, Catalog, Pool)
      assert Spawns.allowed?(world, {:creature, 4}, Catalog)
      Spawns.close(world)
      refute Spawns.allowed?(world, {:creature, 4}, Catalog)
      assert Spawns.allowed?(other, {:game_object, 1}, Catalog)
    end
  end

  defp world_copy(_context) do
    world = WorldRef.instance(529, System.unique_integer([:positive]))
    Spawns.open(world)
    on_exit(fn -> Spawns.close(world) end)
    %{world: world}
  end
end
