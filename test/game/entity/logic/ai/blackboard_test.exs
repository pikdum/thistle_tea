defmodule ThistleTea.Game.Entity.Logic.AI.BT.BlackboardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard

  describe "ready_for?/3" do
    test "defaults to true when unset" do
      assert Blackboard.ready_for?(Blackboard.new(), :next_wander_at, 1_000)
    end

    test "is false when timestamp is in the future" do
      now = 1_000
      blackboard = %Blackboard{next_wander_at: now + 10_000}

      refute Blackboard.ready_for?(blackboard, :next_wander_at, now)
    end

    test "is true when timestamp has passed" do
      now = 1_000
      blackboard = %Blackboard{next_wander_at: now - 1}

      assert Blackboard.ready_for?(blackboard, :next_wander_at, now)
    end
  end

  describe "put_next_at/4" do
    test "stores a future timestamp" do
      now = 1_000
      blackboard = Blackboard.put_next_at(Blackboard.new(), :next_wander_at, 10_000, now)

      assert blackboard.next_wander_at == 11_000
      refute Blackboard.ready_for?(blackboard, :next_wander_at, now)
    end
  end

  describe "delay_until/3" do
    test "returns remaining delay from explicit time" do
      blackboard = %Blackboard{next_wander_at: 11_000}

      assert Blackboard.delay_until(blackboard, :next_wander_at, 1_000) == 10_000
    end
  end
end
