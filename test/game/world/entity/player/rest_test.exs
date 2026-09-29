defmodule ThistleTea.Game.World.Entity.Player.RestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Player.Rest, as: RestCore
  alias ThistleTea.Game.World.Entity.Player.Rest

  @moduletag :dbc_db

  describe "evaluate_zone/2" do
    test "rests a player only in a friendly capital" do
      human = character(1)
      orc = character(2)

      assert RestCore.rest_type(Rest.evaluate_zone(human, 1519)) == :city
      assert RestCore.rest_type(Rest.evaluate_zone(orc, 1637)) == :city
      refute RestCore.resting?(Rest.evaluate_zone(human, 1637))
      refute RestCore.resting?(Rest.evaluate_zone(orc, 1519))
    end

    test "clears city rest when the destination zone is unknown or not a capital" do
      rested = RestCore.start(character(1), :city, 1_000)

      refute RestCore.resting?(Rest.evaluate_zone(rested, 1977))
      refute RestCore.resting?(Rest.evaluate_zone(rested, nil))
    end
  end

  describe "default_zone/1" do
    test "uses the DBC linked zone for maps without navigation data" do
      assert Rest.default_zone(309) == 1977
    end
  end

  defp character(race) do
    %Character{
      unit: %Unit{race: race, level: 50},
      player: %Player{flags: 0, next_level_xp: 100_000},
      internal: %Internal{}
    }
  end
end
