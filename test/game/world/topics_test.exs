defmodule ThistleTea.Game.World.TopicsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.Topics

  describe "publish/2" do
    test "reaches subscribers of the exact key until they unsubscribe" do
      key = Topics.world_facts(WorldRef.open(9_001))
      :ok = Topics.subscribe(key)

      Topics.publish(key, :changed)
      Topics.publish(Topics.world_facts(WorldRef.open(9_002)), :other_world)
      assert_receive :changed
      refute_received :other_world

      :ok = Topics.unsubscribe(key)
      Topics.publish(key, :changed)
      refute_receive :changed, 50
    end
  end

  describe "game events" do
    test "announce starts, stops, and creature data changes to their subscribers" do
      saved = GameEvent.get_events()
      on_exit(fn -> GameEvent.set_events(saved) end)
      event = 9_999

      :ok = GameEvent.subscribe(event)
      :ok = Topics.subscribe(Topics.creature_event(event))
      :ok = Topics.subscribe(Topics.game_events())

      GameEvent.set_events([event | saved])
      assert_receive {:event_start, ^event}
      assert_receive :creature_events_changed
      assert_receive {:game_events_changed, active}
      assert event in active

      GameEvent.set_events(saved)
      assert_receive {:event_stop, ^event}
      assert_receive :creature_events_changed
      assert_receive {:game_events_changed, active}
      refute event in active
    end
  end
end
