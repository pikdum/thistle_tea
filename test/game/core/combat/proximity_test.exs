defmodule ThistleTea.Game.Core.Combat.ProximityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Combat.Proximity
  alias ThistleTea.Game.Core.Combat.Proximity.Aggressor
  alias ThistleTea.Game.Core.Combat.Proximity.Announcement
  alias ThistleTea.Game.Core.Combat.Proximity.Path
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.WorldRef

  describe "contact/4" do
    test "a standing announcer is in contact only inside the radius" do
      announcement = announcement(position: {3.0, 4.0, 0.0})

      assert Proximity.contact(announcement, {0.0, 0.0, 0.0}, 5.0, 0) == {:now, 5.0}
      assert Proximity.contact(announcement, {0.0, 0.0, 0.0}, 4.9, 0) == :never
    end

    test "a walking announcer comes into contact when its path first enters the radius" do
      path = %Path{origin: {0.0, 0.0, 0.0}, nodes: [{100.0, 0.0, 0.0}], started_at: 1_000, duration_ms: 10_000}
      announcement = announcement(path: path)

      assert {:after, delay} = Proximity.contact(announcement, {60.0, 0.0, 0.0}, 10.0, 2_000)
      assert delay == 4_000 + 50
      assert {:now, distance} = Proximity.contact(announcement, {60.0, 0.0, 0.0}, 10.0, 6_000)
      assert_in_delta distance, 10.0, 0.001
    end

    test "counts vertical distance when the path passes over the listener" do
      path = %Path{origin: {-50.0, 0.0, 20.0}, nodes: [{50.0, 0.0, 20.0}], started_at: 0, duration_ms: 10_000}
      announcement = announcement(path: path)

      assert Proximity.contact(announcement, {0.0, 0.0, 0.0}, 15.0, 0) == :never
      assert {:after, _delay} = Proximity.contact(announcement, {0.0, 0.0, 0.0}, 25.0, 0)
    end

    test "a path that passes by or already went past never makes contact" do
      path = %Path{
        origin: {0.0, 0.0, 0.0},
        nodes: [{50.0, 0.0, 0.0}, {50.0, 50.0, 0.0}],
        started_at: 0,
        duration_ms: 10_000
      }

      announcement = announcement(path: path)

      assert Proximity.contact(announcement, {25.0, 30.0, 0.0}, 10.0, 0) == :never
      assert Proximity.contact(announcement, {5.0, 0.0, 0.0}, 2.0, 5_000) == :never
      assert {:after, _delay} = Proximity.contact(announcement, {45.0, 40.0, 0.0}, 10.0, 5_000)
    end

    test "a finished path is judged at its destination" do
      path = %Path{origin: {0.0, 0.0, 0.0}, nodes: [{10.0, 0.0, 0.0}], started_at: 0, duration_ms: 1_000}
      announcement = announcement(path: path)

      assert Proximity.contact(announcement, {12.0, 0.0, 0.0}, 3.0, 5_000) == {:now, 2.0}
    end
  end

  describe "aggressor/1" do
    test "describes an idle creature that aggroes on sight" do
      assert %Aggressor{detection_range: 18.0, level: 12, modifier: 0} = Proximity.aggressor(mob())
    end

    test "is nil for creatures that cannot notice targets right now" do
      assert Proximity.aggressor(%{mob() | internal: %{mob().internal | in_combat: true}}) == nil
      assert Proximity.aggressor(%{mob() | unit: %{mob().unit | health: 0}}) == nil
      assert Proximity.aggressor(%{mob() | internal: %{mob().internal | pet: %Pet{}}}) == nil

      evading = %Blackboard{navigation: %{Blackboard.new().navigation | returning_home?: true}}
      assert Proximity.aggressor(%{mob() | internal: %{mob().internal | blackboard: evading}}) == nil

      passive = %{mob().internal.creature | reaction_state: :passive}
      assert Proximity.aggressor(%{mob() | internal: %{mob().internal | creature: passive}}) == nil
    end

    test "players never aggro by proximity" do
      assert Proximity.aggressor(%Character{unit: %Unit{level: 60, health: 100}, internal: %Internal{}}) == nil
    end
  end

  describe "announcement/4" do
    test "carries the path while walking and drops it once stopped" do
      walking = %{
        mob()
        | internal: %{mob().internal | movement_start_time: 0, movement_start_position: {0.0, 0.0, 0.0}},
          movement_block: %{mob().movement_block | spline_nodes: [{10.0, 0.0, 0.0}], duration: 4_000}
      }

      assert %Announcement{path: %Path{nodes: nodes}, aggressor: %Aggressor{}} =
               Proximity.announcement(walking, 12, {2.5, 0.0, 0.0}, 1_000)

      assert nodes == walking.movement_block.spline_nodes

      assert %Announcement{path: nil} = Proximity.announcement(walking, 12, {10.0, 0.0, 0.0}, 5_000)
    end

    test "long journeys are announced from where the unit stands" do
      travelling = %{
        mob()
        | internal: %{mob().internal | movement_start_time: 0, movement_start_position: {0.0, 0.0, 0.0}},
          movement_block: %{mob().movement_block | spline_nodes: [{1_000.0, 0.0, 0.0}], duration: 100_000}
      }

      assert %Announcement{path: nil} = Proximity.announcement(travelling, 12, {10.0, 0.0, 0.0}, 1_000)
    end
  end

  describe "extent/1" do
    test "covers the announcer's reach around its whole path" do
      path = %Path{origin: {0.0, 0.0, 0.0}, nodes: [{40.0, -20.0, 0.0}], started_at: 0, duration_ms: 1_000}

      assert Proximity.extent(announcement(position: {10.0, 0.0, 0.0}, path: path)) == {-75.0, -95.0, 115.0, 75.0}

      aggressor = %Aggressor{detection_range: 60.0, level: 1, modifier: 10}
      assert Proximity.extent(announcement(aggressor: aggressor)) == {-95.0, -95.0, 95.0, 95.0}
    end
  end

  defp announcement(opts) do
    %Announcement{
      guid: 1,
      world: WorldRef.open(0),
      position: Keyword.get(opts, :position, {0.0, 0.0, 0.0}),
      level: 10,
      path: Keyword.get(opts, :path),
      aggressor: Keyword.get(opts, :aggressor)
    }
  end

  defp mob do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 12, health: 100, max_health: 100, flags: 0},
      internal: %Internal{world: WorldRef.open(0), in_combat: false, creature: %Creature{detection_range: 18.0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
