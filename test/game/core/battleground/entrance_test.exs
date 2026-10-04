defmodule ThistleTea.Game.Core.Battleground.EntranceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Battleground.Entrance
  alias ThistleTea.Game.Core.Battleground.Template

  @warsong %Template{type_id: 2, map_id: 489, min_level: 10, max_level: 60}
  @alterac %Template{type_id: 1, map_id: 30, min_level: 51, max_level: 60}

  describe "from_row/1" do
    test "reads the portal's team, battleground, and exit" do
      row = %{
        id: 3650,
        team: 469,
        bg_template: 2,
        exit_map: 1,
        exit_position_x: 1454.12,
        exit_position_y: -1858.47,
        exit_position_z: 126.402,
        exit_orientation: 6.194
      }

      assert %Entrance{trigger_id: 3650, team: :alliance, type_id: 2, exit_map: 1} = entrance = Entrance.from_row(row)
      assert entrance.exit_position == {1454.12, -1858.47, 126.402, 6.194}
      assert Entrance.from_row(%{row | team: 67}).team == :horde
    end
  end

  describe "admit/4" do
    test "admits its own team within the battleground's levels" do
      alliance = %Entrance{team: :alliance, type_id: 2}
      assert Entrance.admit(alliance, @warsong, :alliance, 10) == :ok
      assert Entrance.admit(alliance, @warsong, :alliance, 60) == :ok
    end

    test "names the team and level the portal requires" do
      horde = %Entrance{team: :horde, type_id: 2}
      expected = {:error, "You must be in the Horde and at least 10th level to enter."}
      assert Entrance.admit(horde, @warsong, :alliance, 60) == expected
      assert Entrance.admit(horde, @warsong, :horde, 9) == expected

      assert Entrance.admit(%{horde | type_id: 1}, @alterac, :horde, 50) ==
               {:error, "You must be in the Horde and at least 51st level to enter."}
    end
  end
end
