defmodule ThistleTea.Game.World.System.MinionsOfOmenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.MinionsOfOmen, as: Watch
  alias ThistleTea.Game.Core.GameEvent.Schedule
  alias ThistleTea.Game.Core.GameEvent.Schedule.Entry
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.MinionsOfOmen
  alias ThistleTea.Test.Unique

  setup [:watch]

  describe "launched/1" do
    test "fireworks bring the minions out and then call Omen", %{server: server, events: events} do
      assert GameEvent.get_events(events) == []
      refute Enum.any?(1..2, fn _launch -> MinionsOfOmen.launched(server) end)
      assert GameEvent.get_events(events) == []

      refute Enum.any?(3..19, fn _launch -> MinionsOfOmen.launched(server) end)
      assert GameEvent.get_events(events) == [43]
      assert MinionsOfOmen.launched(server)
      refute MinionsOfOmen.launched(server)
    end
  end

  describe "omen_arrived/2" do
    test "the minions leave when Omen leaves the world", %{server: server, events: events} do
      for _launch <- 1..20, do: MinionsOfOmen.launched(server)
      guid = Guid.from_low_guid(:mob, Watch.omen(), Unique.integer())
      parent = self()

      omen =
        spawn(fn ->
          {:ok, _} = Entity.register(guid)
          send(parent, :registered)
          receive do: (:leave -> :ok)
        end)

      assert_receive :registered
      MinionsOfOmen.omen_arrived(guid, server)
      MinionsOfOmen.omen_fell(server)
      :sys.get_state(server)
      assert GameEvent.get_events(events) == [43]

      send(omen, :leave)
      eventually(fn -> GameEvent.get_events(events) == [] end)
      refute MinionsOfOmen.launched(server)
    end
  end

  describe "a call Omen never answers" do
    @tag arrival_ms: 20
    test "is let go so the fireworks can call him again", %{server: server, events: events} do
      assert Enum.count(1..20, fn _launch -> MinionsOfOmen.launched(server) end) == 1
      eventually(fn -> not :sys.get_state(server).watch.omen_out? end)
      assert GameEvent.get_events(events) == [43]
      assert Enum.count(1..20, fn _launch -> MinionsOfOmen.launched(server) end) == 1
    end
  end

  defp watch(context) do
    id = Unique.integer()
    events = String.to_atom("minions_of_omen_events_#{id}")
    server = String.to_atom("minions_of_omen_#{id}")
    schedule = Schedule.new([%Entry{id: 43, rule: Watch}])

    start_supervised!(
      {GameEvent,
       name: events, schedule: schedule, now: fn -> ~U[2026-10-03 12:00:00Z] end, on_change: fn _, _ -> :ok end}
    )

    start_supervised!(
      {MinionsOfOmen, name: server, game_events: events, now: fn -> 0 end, arrival_ms: context[:arrival_ms] || 10_000}
    )

    %{server: server, events: events}
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        :ok

      attempts > 0 ->
        Process.sleep(10)
        eventually(check, attempts - 1)

      true ->
        flunk("condition never held")
    end
  end
end
