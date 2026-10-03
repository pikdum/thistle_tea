defmodule ThistleTea.Game.World.System.ScourgeInvasionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.Schedule
  alias ThistleTea.Game.Core.GameEvent.Schedule.Entry
  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion, as: Invasion
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.ScourgeInvasion
  alias ThistleTea.Game.World.Topics
  alias ThistleTea.Test.Unique

  @now 1_800_000_000
  @zone_events [90, 91, 92, 93, 94, 95]

  setup [:invasion]

  describe "start_link/1" do
    test "the invasion starts called off", %{server: server, events: events} do
      assert %{enabled?: false, victories: 0} = ScourgeInvasion.status(server)
      assert GameEvent.get_events(events) == []
    end
  end

  describe "enable/1" do
    test "the first wave strikes every zone under a Mouth of Kel'Thuzad", ctx do
      %{server: server, events: events, variables: variables, topic: topic} = ctx
      :ok = Topics.subscribe(topic)

      :ok = ScourgeInvasion.enable(server)

      assert GameEvent.get_events(events) == [17 | @zone_events]
      assert map_size(:sys.get_state(server).mouths) == 6
      assert ServerVariables.get(Invasion.zone(:winterspring).remaining_variable, variables) == 3
      assert_receive {:world_states_changed, states}
      assert {2259, 1} in states
      assert {2284, 3} in states
    end
  end

  describe "necropolis_fell/2" do
    test "the last necropolis to fall wins the zone at the next pass", ctx do
      %{server: server, events: events, variables: variables} = ctx
      :ok = ScourgeInvasion.enable(server)

      for _necropolis <- 1..3, do: ScourgeInvasion.necropolis_fell(618, server)
      send(server, {:update, :sys.get_state(server).timer})

      assert %{victories: 1} = ScourgeInvasion.status(server)
      refute Map.has_key?(:sys.get_state(server).mouths, :winterspring)
      assert GameEvent.get_events(events) == [17, 91, 92, 93, 94, 95]
      assert ServerVariables.get(17_001, variables) == 618
      assert ServerVariables.get(Invasion.zone(:winterspring).attack_time_variable, variables) == @now + 3_000
    end
  end

  describe "attack/2" do
    test "sends the Scourge to a zone at once", %{server: server, events: events} do
      :ok = ScourgeInvasion.enable(server)
      for _necropolis <- 1..3, do: ScourgeInvasion.necropolis_fell(618, server)
      send(server, {:update, :sys.get_state(server).timer})

      assert ScourgeInvasion.attack(:winterspring, server) == :ok
      assert 90 in GameEvent.get_events(events)
      assert ScourgeInvasion.attack(:winterspring, server) == {:error, :already_attacked}
    end
  end

  describe "disable/1" do
    test "calls the Scourge off and clears the map", %{server: server, events: events, topic: topic} do
      :ok = ScourgeInvasion.enable(server)
      :ok = Topics.subscribe(topic)

      :ok = ScourgeInvasion.disable(server)

      assert GameEvent.get_events(events) == []
      assert :sys.get_state(server).mouths == %{}
      assert_receive {:world_states_changed, states}
      assert {2259, 0} in states
    end
  end

  describe "world_states/2" do
    test "shows the invasion only while it runs", %{server: server, events: events, variables: variables} do
      assert ScourgeInvasion.world_states(variables, events) == []

      :ok = ScourgeInvasion.enable(server)

      assert {2219, 0} in ScourgeInvasion.world_states(variables, events)
    end
  end

  defp invasion(_context) do
    id = Unique.integer()
    variables = String.to_atom("scourge_invasion_variables_#{id}")
    events = String.to_atom("scourge_invasion_events_#{id}")
    server = String.to_atom("scourge_invasion_#{id}")
    topic = "scourge_invasion_test/#{id}"
    ServerVariables.init(variables)

    schedule = Schedule.new(Enum.map(Invasion.events(), &%Entry{id: &1, rule: Invasion}))

    start_supervised!(
      {GameEvent,
       name: events, schedule: schedule, now: fn -> ~U[2026-10-03 12:00:00Z] end, on_change: fn _, _ -> :ok end}
    )

    start_supervised!(
      {ScourgeInvasion,
       name: server,
       variables: variables,
       game_events: events,
       weather: nil,
       topic: topic,
       clock: fn -> @now end,
       rolls: Rolls.fixed(attack_delay: 3_000),
       update_ms: to_timeout(hour: 1),
       enabled?: false,
       summon: &summon/1}
    )

    %{server: server, events: events, variables: variables, topic: topic}
  end

  defp summon(_zone) do
    pid = spawn_link(fn -> Process.sleep(:infinity) end)
    {:ok, Guid.from_low_guid(:mob, 16_995, Unique.integer()), pid}
  end
end
