defmodule ThistleTea.Game.Player.RestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Rest, as: RestLogic
  alias ThistleTea.Game.Player.Rest

  @moduletag :dbc_db

  describe "evaluate_zone/2" do
    test "rests a player only in a friendly capital" do
      human = character(1)
      orc = character(2)

      assert RestLogic.rest_type(Rest.evaluate_zone(human, 1519)) == :city
      assert RestLogic.rest_type(Rest.evaluate_zone(orc, 1637)) == :city
      refute RestLogic.resting?(Rest.evaluate_zone(human, 1637))
      refute RestLogic.resting?(Rest.evaluate_zone(orc, 1519))
    end

    test "clears city rest when the destination zone is unknown or not a capital" do
      rested = RestLogic.start(character(1), :city, 1_000)

      refute RestLogic.resting?(Rest.evaluate_zone(rested, 1977))
      refute RestLogic.resting?(Rest.evaluate_zone(rested, nil))
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
