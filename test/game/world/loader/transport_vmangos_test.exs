defmodule ThistleTea.Game.World.Loader.TransportVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Transport

  @moduletag :vmangos_db

  describe "ship_specs/0" do
    test "selects the vanilla transport templates and latest schedule periods" do
      specs = Transport.ship_specs()

      assert length(specs) == 9

      assert %{
               name: "Orgrimmar and Undercity",
               path_id: 302,
               move_speed: 30,
               accel_rate: 1,
               period_ms: 356_284
             } = Enum.find(specs, &(&1.entry == 164_871))

      assert %{path_id: 436, period_ms: 1_208_014} =
               Enum.find(specs, &(&1.entry == 181_056))
    end
  end
end
