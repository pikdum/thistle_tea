defmodule ThistleTea.Game.Battleground.AlteracValley.NodeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground.AlteracValley.Node

  describe "all/0" do
    test "initializes all seven graveyards and eight faction towers" do
      nodes = Node.all()
      assert map_size(nodes) == 15
      assert Enum.count(nodes, fn {_id, node} -> node.kind == :graveyard end) == 7
      assert Enum.count(nodes, fn {_id, node} -> node.kind == :tower end) == 8

      for id <- [0, 1, 2, 7, 8, 9, 10], do: assert(Node.controlled_by(nodes[id]) == :alliance)
      for id <- [4, 5, 6, 11, 12, 13, 14], do: assert(Node.controlled_by(nodes[id]) == :horde)
      assert Node.controlled_by(nodes[3]) == nil
      assert Node.event_state(nodes[3]) == 5
      assert Node.defender_events(nodes[3]) == [{18, 8}]
    end
  end

  describe "assault/3" do
    test "defends immediately and rejects both stale capture timers after a new assault" do
      node = Node.new(2)
      assert {:unchanged, ^node} = Node.assault(node, :alliance, 0)
      {:assaulted, attacked} = Node.assault(node, :horde, 100)
      assert attacked.point.capture_at == 300_100
      assert Node.controlled_by(attacked) == nil
      assert {:unchanged, ^attacked} = Node.assault(attacked, :horde, 200)
      {:defended, defended} = Node.assault(attacked, :alliance, 300)
      assert Node.controlled_by(defended) == :alliance
      assert defended.point.capture_at == nil
      assert {:unchanged, ^defended} = Node.capture(defended, attacked.point.revision, 400_000)

      {:assaulted, attacked_again} = Node.assault(defended, :horde, 400)
      assert {:unchanged, ^attacked_again} = Node.capture(attacked_again, attacked.point.revision, 400_000)
      assert {:captured, captured} = Node.capture(attacked_again, attacked_again.point.revision, 300_400)
      assert Node.controlled_by(captured) == :horde
      refute captured.destroyed?
      assert {:assaulted, _recapture} = Node.assault(captured, :alliance, 300_500)
    end

    test "Snowfall counterassaults restart the full timer until its first capture" do
      neutral = Node.new(3)
      {:assaulted, alliance} = Node.assault(neutral, :alliance, 0)
      {:assaulted, horde} = Node.assault(alliance, :horde, 299_000)
      assert horde.point.owner == nil
      assert horde.point.capture_at == 599_000
      assert {:unchanged, ^horde} = Node.capture(horde, alliance.point.revision, 300_000)
      assert {:unchanged, ^horde} = Node.capture(horde, horde.point.revision, 598_999)
      {:captured, captured} = Node.capture(horde, horde.point.revision, 599_000)
      assert Node.controlled_by(captured) == :horde
      {:assaulted, contested} = Node.assault(captured, :alliance, 600_000)
      assert {:defended, defended} = Node.assault(contested, :horde, 600_001)
      assert Node.controlled_by(defended) == :horde
    end
  end

  describe "capture/3" do
    test "tower destruction is permanent and replaces the base marshal event" do
      for id <- 7..14 do
        tower = Node.new(id)
        enemy = if tower.home_team == :alliance, do: :horde, else: :alliance
        {:assaulted, attacked} = Node.assault(tower, enemy, 100)
        assert {:unchanged, ^attacked} = Node.capture(attacked, attacked.point.revision, 300_099)
        {:captured, destroyed} = Node.capture(attacked, attacked.point.revision, 300_100)
        assert destroyed.destroyed?
        assert Node.controlled_by(destroyed) == nil
        assert {:unchanged, ^destroyed} = Node.assault(destroyed, tower.home_team, 400_000)
        assert {:unchanged, ^destroyed} = Node.assault(destroyed, enemy, 400_000)
        assert {:unchanged, ^destroyed} = Node.capture(destroyed, attacked.point.revision, 400_000)
        state = if enemy == :alliance, do: 1, else: 3
        assert {15 + id, state} in Node.defender_events(destroyed)
      end
    end
  end

  describe "defender_events/2" do
    test "selects each armor tier without changing the marshal tier" do
      for upgrade <- 0..3 do
        assert Node.defender_events(Node.new(0), upgrade) == [{15, upgrade}]
        assert Node.defender_events(Node.new(4), upgrade) == [{19, 4 + upgrade}]
        assert Node.defender_events(Node.new(7), upgrade) == [{22, 1}, {30, upgrade}]
        assert Node.defender_events(Node.new(11), upgrade) == [{26, 3}, {34, 4 + upgrade}]
        assert Node.defender_events(Node.new(3), upgrade) == [{18, 8}]
      end
    end
  end

  describe "world_states/1" do
    test "clears old map icons through assault, defense, and capture" do
      for {_id, node} <- Node.all() do
        enemy = if node.home_team == :alliance, do: :horde, else: :alliance
        {:assaulted, attacked} = Node.assault(node, enemy, 0)
        {:captured, captured} = Node.capture(attacked, attacked.point.revision, 300_000)

        for version <- [node, attacked, captured] do
          states = Node.world_states(version)
          assert Enum.count(states, fn {_field, value} -> value == 1 end) == 1
          assert Enum.all?(states, fn {_field, value} -> value in [0, 1] end)
        end

        refute Node.world_states(node) == Node.world_states(attacked)
        refute Node.world_states(attacked) == Node.world_states(captured)
      end

      assert {1_966, 1} in Node.world_states(Node.new(3))
      assert {1_326, 1} in Node.world_states(Node.new(0))
      assert {1_395, 1} in Node.world_states(Node.new(11))
    end
  end
end
