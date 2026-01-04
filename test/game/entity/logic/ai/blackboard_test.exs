defmodule ThistleTea.Game.Entity.Logic.AI.BT.BlackboardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Time

  test "ready_for? defaults to true when unset" do
    assert Blackboard.ready_for?(Blackboard.new(), :next_wander_at)
  end

  test "ready_for? is false when timestamp is in the future" do
    now = Time.now()
    blackboard = %Blackboard{next_wander_at: now + 10_000}

    refute Blackboard.ready_for?(blackboard, :next_wander_at)
  end

  test "ready_for? is true when timestamp has passed" do
    now = Time.now()
    blackboard = %Blackboard{next_wander_at: now - 1}

    assert Blackboard.ready_for?(blackboard, :next_wander_at)
  end

  test "put_next_at stores a future timestamp" do
    before = Time.now()
    blackboard = Blackboard.put_next_at(Blackboard.new(), :next_wander_at, 10_000)
    after_time = Time.now()

    assert blackboard.next_wander_at >= before + 10_000
    assert blackboard.next_wander_at <= after_time + 10_000
    refute Blackboard.ready_for?(blackboard, :next_wander_at)
  end
end
