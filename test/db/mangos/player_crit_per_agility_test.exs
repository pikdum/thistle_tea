defmodule ThistleTea.DB.Mangos.PlayerCritPerAgilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.PlayerCritPerAgility

  @moduletag :vmangos_db

  describe "rate/2" do
    test "reads a class's agility per crit percent at a level, and its last level beyond the table" do
      assert_in_delta PlayerCritPerAgility.rate(1, 30), 10.395, 0.0001
      assert_in_delta PlayerCritPerAgility.rate(8, 1), 11.1111, 0.0001
      assert PlayerCritPerAgility.rate(4, 70) == PlayerCritPerAgility.rate(4, 60)
    end
  end
end
