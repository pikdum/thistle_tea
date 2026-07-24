defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob.CallForHelpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Event

  describe "maybe_enqueue_call_assistance/2" do
    test "queues a call-assistance event for a regular mob" do
      mob = MobBT.maybe_enqueue_call_assistance(mob(), 42)

      assert [%Event{type: :call_assistance, target_guid: 42}] = mob.internal.events
    end

    test "does not queue for pets or mobs with the range disabled" do
      pet = mob(pet: %Pet{owner_guid: 7})
      assert MobBT.maybe_enqueue_call_assistance(pet, 42).internal.events in [nil, []]

      disabled = mob(range: 0.0)
      assert MobBT.maybe_enqueue_call_assistance(disabled, 42).internal.events in [nil, []]
    end
  end

  describe "call_for_help_step/3" do
    test "queues a call-for-help pulse when dragged from spawn" do
      mob = mob(position: {20.0, 0.0, 0.0, 0.0}, target: 42)

      {:success, mob, blackboard} = MobBT.call_for_help_step(mob, Blackboard.new(), 5_000)

      assert [%Event{type: :call_for_help, target_guid: 42}] = mob.internal.events
      assert blackboard.next_call_for_help_at == 6_000
    end

    test "stays quiet near spawn and between pulses" do
      near_spawn = mob(position: {5.0, 0.0, 0.0, 0.0}, target: 42)
      {:success, near_spawn, _blackboard} = MobBT.call_for_help_step(near_spawn, Blackboard.new(), 5_000)
      assert near_spawn.internal.events in [nil, []]

      dragged = mob(position: {20.0, 0.0, 0.0, 0.0}, target: 42)
      waiting = %{Blackboard.new() | next_call_for_help_at: 6_000}
      {:success, dragged, ^waiting} = MobBT.call_for_help_step(dragged, waiting, 5_000)
      assert dragged.internal.events in [nil, []]
    end

    test "needs a live target and an enabled range" do
      no_target = mob(position: {20.0, 0.0, 0.0, 0.0}, target: 0)
      {:success, no_target, _blackboard} = MobBT.call_for_help_step(no_target, Blackboard.new(), 5_000)
      assert no_target.internal.events in [nil, []]

      disabled = mob(position: {20.0, 0.0, 0.0, 0.0}, target: 42, range: 0.0)
      {:success, disabled, _blackboard} = MobBT.call_for_help_step(disabled, Blackboard.new(), 5_000)
      assert disabled.internal.events in [nil, []]
    end
  end

  defp mob(opts \\ []) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 10, target: Keyword.get(opts, :target, 0)},
      movement_block: %MovementBlock{position: Keyword.get(opts, :position, {0.0, 0.0, 0.0, 0.0})},
      internal: %Internal{
        pet: Keyword.get(opts, :pet),
        spawn: %Spawn{position: {0.0, 0.0, 0.0}},
        creature: %Creature{call_for_help_range: Keyword.get(opts, :range, 5.0)}
      }
    }
  end
end
