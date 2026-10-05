defmodule ThistleTea.Game.World.Entity.PlacedRitualTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectSpawn
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Test.Unique

  describe "handle_cast/2 gameobject_use" do
    test "the first participant casts the completion spell once enough have gathered" do
      first = Unique.integer()
      {:ok, _} = Entity.register(first)
      altar = altar()
      {:ok, pid} = World.start_entity(altar)
      guid = altar.object.guid

      GenServer.cast(pid, {:gameobject_use, first, 40})
      GenServer.cast(pid, {:gameobject_use, Unique.integer(), 40})
      assert %{users: users, completed?: false, first_user_guid: ^first} = :sys.get_state(pid).internal.ritual
      assert MapSet.size(users) == 2
      refute_received {:"$gen_cast", {:trigger_spell, _spell_id, _target, _opts}}

      GenServer.cast(pid, {:gameobject_use, Unique.integer(), 40})

      assert %{users: users, completed?: false, first_user_guid: nil} = :sys.get_state(pid).internal.ritual
      assert users == MapSet.new()
      assert_received {:"$gen_cast", {:trigger_spell, 10_340, ^guid, [triggered: true]}}
      assert_received {:"$gen_cast", {:finish_game_object_channel, ^guid}}
    end
  end

  defp altar do
    template = %GameObjectTemplate{entry: 133_234, type: 18, size: 1.0, data: [3, 10_340, 0, 1, 0, 0, 0, 0]}
    altar = GameObject.build(template, %GameObjectSpawn{guid: Unique.integer(), entry: 133_234, map_id: 900_070})
    on_exit(fn -> World.stop_entity(altar.object.guid) end)
    altar
  end
end
