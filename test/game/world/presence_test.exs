defmodule ThistleTea.Game.World.PresenceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.ClientMotion
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "enter/2" do
    test "publishes metadata and position from one character snapshot" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      on_exit(fn -> Presence.leave(character) end)

      assert :ok = Presence.enter(character, %{name: "Alice"})

      assert Metadata.query(character.object.guid, [:name, :area, :orientation, :world]) == %{
               name: "Alice",
               area: 12,
               orientation: 1.5
             }

      assert SpatialHash.get_entity(character.object.guid) ==
               {character.object.guid, WorldRef.open(0), 1.0, 2.0, 3.0}
    end

    test "publishes the active farsight viewpoint" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      character = %{character | player: %Player{farsight: 4321}}
      on_exit(fn -> Presence.leave(character) end)

      assert :ok = Presence.enter(character, %{})
      assert Metadata.query(character.object.guid, [:viewpoint]) == %{viewpoint: 4321}
    end
  end

  describe "relocate/2" do
    test "moves spatial and metadata location together while preserving other metadata" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      on_exit(fn -> Presence.leave(character) end)
      Presence.enter(character, %{name: "Alice"})

      relocated = character(WorldRef.instance(389, 7), {4.0, 5.0, 6.0, 2.5}, 43, character.object.guid)

      assert :ok = Presence.relocate(relocated, %{moving_until: 900})

      assert Metadata.query(character.object.guid, [:name, :area, :orientation, :moving_until]) == %{
               name: "Alice",
               area: 43,
               orientation: 2.5,
               moving_until: 900
             }

      assert SpatialHash.get_entity(character.object.guid) ==
               {character.object.guid, WorldRef.instance(389, 7), 4.0, 5.0, 6.0}
    end
  end

  describe "relocate_client/5" do
    test "publishes metadata, stationary origin, and bounded motion together" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 0.0}, 12)
      on_exit(fn -> Presence.leave(character) end)

      assert :ok = Presence.relocate_client(character, %{moving_until: 1_750}, {70.0, 0.0, 0.0}, 1_000, 750)

      assert %ClientMotion{origin: origin, velocity: velocity} = Position.projection(character.object.guid)
      assert origin == {1.0, 2.0, 3.0}
      assert velocity == {70.0, 0.0, 0.0}

      assert Position.get(character.object.guid, 1_100) == {WorldRef.open(0), 8.0, 2.0, 3.0}
    end
  end

  describe "leave/1" do
    test "withdraws metadata and spatial position together" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      Presence.enter(character, %{name: "Alice"})

      assert :ok = Presence.leave(character)
      assert Metadata.get(character.object.guid) == nil
      assert SpatialHash.get_entity(character.object.guid) == nil
    end
  end

  defp character(world, position, area, guid \\ nil) do
    %Character{
      object: %Object{guid: guid || Guid.from_low_guid(:player, System.unique_integer([:positive]))},
      internal: %Internal{world: world, area: area},
      movement_block: %MovementBlock{position: position}
    }
  end
end
