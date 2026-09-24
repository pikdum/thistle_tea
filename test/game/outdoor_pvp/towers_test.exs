defmodule ThistleTea.Game.OutdoorPvp.TowersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.OutdoorPvp.Towers
  alias ThistleTea.Game.OutdoorPvp.Towers.Participant
  alias ThistleTea.Game.WorldRef

  describe "advance/3" do
    setup [:towers]

    test "counts unique eligible participants in the matching open world", %{towers: towers} do
      alliance = participant(1, :northpass, :alliance)
      horde = participant(2, :northpass, :horde)

      excluded = [
        %{alliance | guid: 3, eligible?: false},
        %{alliance | guid: 4, world: WorldRef.instance(0, 1)},
        %{alliance | guid: 5, world: WorldRef.open(1)},
        %{alliance | guid: 6, position: {0.0, 0.0, 0.0}}
      ]

      tied = Towers.advance(towers, [alliance, alliance, horde | excluded], 1000)
      assert tied.members == %{1 => {:northpass, :alliance}, 2 => {:northpass, :horde}}
      assert tied.points.northpass.progress == 0
      advancing = Towers.advance(tied, [alliance], 1000)
      assert advancing.members == %{1 => {:northpass, :alliance}}
      assert advancing.points.northpass.progress == 1000
    end

    test "captures independently, upgrades faction rewards, and retains abandoned progress", %{towers: towers} do
      owned =
        Towers.advance(towers, [participant(1, :northpass, :alliance), participant(2, :crown_guard, :horde)], 240_000)

      assert Towers.counts(owned) == %{alliance: 1, horde: 1}
      assert Towers.buff(owned, :alliance) == 11_413
      assert Towers.buff(owned, :horde) == 30_880
      assert Towers.ownership_changes(towers, owned) == [{:crown_guard, nil, :horde}, {:northpass, nil, :alliance}]
      upgraded = Towers.advance(owned, [participant(1, :eastwall, :alliance)], 240_000)
      assert upgraded.points.northpass == %{owned.points.northpass | difference: 0}
      assert Towers.counts(upgraded) == %{alliance: 2, horde: 1}
      assert Towers.buff(upgraded, :alliance) == 11_414
      assert Towers.ownership_changes(owned, upgraded) == [{:eastwall, nil, :alliance}]
    end

    test "removing ownership downgrades rewards once", %{towers: towers} do
      owned = Towers.advance(towers, [participant(1, :northpass, :alliance)], 240_000)
      neutral = Towers.advance(owned, [participant(2, :northpass, :horde)], 1000)
      assert Towers.ownership_changes(owned, neutral) == [{:northpass, :alliance, nil}]
      assert Towers.buff(neutral, :alliance) == nil
      assert Towers.ownership_changes(neutral, Towers.advance(neutral, [], 1000)) == []
    end
  end

  describe "world_states/1" do
    setup [:towers]

    test "projects every tower and the nearby participant's meter", %{towers: towers} do
      towers = Towers.advance(towers, [participant(1, :northpass, :alliance)], 240_000)
      states = Map.new(Towers.world_states(towers))
      assert map_size(states) == 30
      assert states[2327] == 1
      assert states[2328] == 0
      assert states[2364] == 1
      assert states[2352] == 0
      assert states[2361] == 1
      assert Towers.slider_states(towers, 1) == [{2426, 1}, {2428, 20}, {2427, 60}]
      assert Towers.slider_states(towers, 2) == [{2426, 0}]
    end
  end

  describe "updates/3" do
    setup [:towers]

    test "orders the meter last and removes it when participation ends", %{towers: towers} do
      active = Towers.advance(towers, [participant(1, :northpass, :alliance)], 1000)
      assert Enum.take(Towers.updates(towers, active, 1), -3) == [{2426, 1}, {2428, 20}, {2427, 51}]

      stopped =
        Towers.advance(active, [participant(1, :northpass, :alliance), participant(2, :northpass, :horde)], 1000)

      assert List.last(Towers.updates(active, stopped, 1)) == {2427, 51}

      unchanged =
        Towers.advance(stopped, [participant(1, :northpass, :alliance), participant(2, :northpass, :horde)], 1000)

      assert Towers.updates(stopped, unchanged, 1) == []
      absent = Towers.advance(unchanged, [], 1000)
      assert Towers.updates(unchanged, absent, 1) == [{2426, 0}]
    end

    test "resends the current meter after a distant tower changes", %{towers: towers} do
      participants = [participant(1, :northpass, :alliance)]
      active = Towers.advance(towers, participants, 1000)
      current = Towers.advance(active, participants ++ [participant(2, :eastwall, :horde)], 1)
      assert List.last(Towers.updates(active, current, 1)) == {2427, 51}
      assert List.last(Towers.updates(active, current, 2)) == {2427, 50}
    end
  end

  describe "capture_recipients/3" do
    test "credits eligible allies within the reward radius, including outside the capture meter" do
      {x, y, z} = Plaguelands.credit_position(:northpass, :alliance)
      ally = %{participant(1, :northpass, :alliance) | position: {x + 90, y, z}}

      excluded = [
        %{ally | guid: 2, position: {x + 101, y, z}},
        %{ally | guid: 3, team: :horde},
        %{ally | guid: 4, eligible?: false},
        %{ally | guid: 5, world: WorldRef.instance(0, 1)}
      ]

      assert Towers.capture_recipients([ally | excluded], :northpass, :alliance) == [1]
      assert Towers.capture_recipients([ally], :northpass, nil) == []
    end
  end

  defp towers(_context) do
    templates =
      Map.new(Plaguelands.towers(), fn {_id, definition} ->
        {definition.entry,
         %Template{
           entry: definition.entry,
           radius: 80,
           display_state: 2426,
           position_state: 2427,
           neutral_state: 2428,
           neutral_percent: 20,
           min_time: 480,
           max_time: 1200
         }}
      end)

    %{towers: Towers.new(templates)}
  end

  defp participant(guid, tower, team) do
    {x, y, z, _orientation} = Plaguelands.towers()[tower].position
    %Participant{guid: guid, team: team, world: WorldRef.open(0), position: {x, y, z}, eligible?: true}
  end
end
