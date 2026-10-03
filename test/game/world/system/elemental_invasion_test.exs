defmodule ThistleTea.Game.World.System.ElementalInvasionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.ElementalInvasion, as: Invasion
  alias ThistleTea.Game.Core.GameEvent.Schedule
  alias ThistleTea.Game.Core.GameEvent.Schedule.Entry
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Game.World.System.ElementalInvasion
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Test.Unique

  @rifts [68, 69, 70, 71]

  setup [:invasion]

  describe "start_link/1" do
    test "a world starts invaded with every rift open", %{events: events, variables: variables} do
      assert GameEvent.get_events(events) == [13 | @rifts]
      assert Enum.all?(Invasion.elements(), &(ElementalInvasion.stage(&1, variables) == 1))
    end
  end

  describe "invader_slain/2" do
    test "the fiftieth invader slain opens the next stage", %{server: server, variables: variables} do
      for _invader <- 1..49, do: ElementalInvasion.invader_slain(:fire, server)
      :sys.get_state(server)
      assert {ServerVariables.get(30_008, variables), ServerVariables.get(30_012, variables)} == {1, 49}

      ElementalInvasion.invader_slain(:fire, server)
      :sys.get_state(server)
      assert {ServerVariables.get(30_008, variables), ServerVariables.get(30_012, variables)} == {2, 0}
      assert ServerVariables.get(30_011, variables) == 1
    end
  end

  describe "the hourly clock" do
    test "brings each lord out at the boss stage", %{server: server, events: events, variables: variables} do
      for _hour <- 1..4, do: send(server, :hour)
      :sys.get_state(server)

      assert Enum.all?(Invasion.elements(), &(ElementalInvasion.stage(&1, variables) == 5))
      assert GameEvent.get_events(events) == [13 | @rifts] ++ [72, 73, 74, 75]
    end
  end

  describe "a fallen lord" do
    test "closes its rifts, leaves once looted, and the last one rests the invasion", ctx do
      %{server: server, events: events, variables: variables} = ctx
      for _hour <- 1..4, do: send(server, :hour)
      :sys.get_state(server)

      fall(server, variables, 30_008)
      assert GameEvent.get_events(events) == [13, 69, 70, 71, 72, 73, 74, 75]
      eventually(fn -> GameEvent.get_events(events) == [13, 69, 70, 71, 73, 74, 75] end)

      for variable <- [30_009, 30_010, 30_011], do: fall(server, variables, variable)
      eventually(fn -> GameEvent.get_events(events) == [] end)
      eventually(fn -> GameEvent.get_events(events) == [13 | @rifts] end)
      assert Enum.all?(Invasion.elements(), &(ElementalInvasion.stage(&1, variables) == 1))
    end
  end

  defp invasion(_context) do
    id = Unique.integer()
    variables = String.to_atom("elemental_invasion_variables_#{id}")
    events = String.to_atom("elemental_invasion_events_#{id}")
    server = String.to_atom("elemental_invasion_#{id}")
    ServerVariables.init(variables)

    schedule = Schedule.new(Enum.map(Invasion.events(), &%Entry{id: &1, rule: Invasion}))

    start_supervised!(
      {GameEvent,
       name: events, schedule: schedule, now: fn -> ~U[2026-10-03 12:00:00Z] end, on_change: fn _, _ -> :ok end}
    )

    start_supervised!(
      {ElementalInvasion,
       name: server,
       variables: variables,
       game_events: events,
       hour_ms: to_timeout(hour: 1),
       looting_ms: 100,
       rest_ms: fn -> 150 end}
    )

    %{server: server, events: events, variables: variables}
  end

  defp fall(server, variables, variable) do
    :ok = ServerVariables.put(variable, 6, variables)
    send(server, {:server_variable_changed, variable})
    :sys.get_state(server)
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
