defmodule ThistleTea.Game.Entity.Server.Mob.PetLifecycleTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.WorldRef

  describe "child_spec/1" do
    test "suspension snapshots final progress without restarting the supervised pet" do
      guid = Guid.runtime(:pet, 2960)
      owner = System.unique_integer([:positive]) + 10_000_000
      Entity.register(owner)

      pet = %Mob{
        object: %Object{guid: guid, entry: 2960},
        unit: %Unit{health: 100, max_health: 100, level: 49, power5: 166_500, pet_experience: 123, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: WorldRef.open(451),
          pet: %Pet{owner_guid: owner, kind: :hunter, profile: :combat},
          creature: %Creature{},
          spawn: %Spawn{},
          spellbook: %{}
        }
      }

      {:ok, pid} = World.start_entity(pet)
      on_exit(fn -> if Entity.online?(guid), do: World.stop_entity(guid) end)
      ref = Process.monitor(pid)
      assert {:ok, 166_500, false, %PetProgress{level: 49, xp: 123}} = Entity.call(guid, :suspend_hunter_pet)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert MobServer.child_spec(pet).restart == :temporary
      refute Entity.online?(guid)
    end
  end
end
