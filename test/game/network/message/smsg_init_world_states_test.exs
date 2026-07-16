defmodule ThistleTea.Game.Network.Message.SmsgInitWorldStatesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgInitWorldStates

  describe "to_binary/1" do
    test "encodes the map, area, and states" do
      message = %SmsgInitWorldStates{map: 389, area: 2437, states: [{1, 2}, {3, 4}]}

      assert SmsgInitWorldStates.to_binary(message) ==
               <<389::little-size(32), 2437::little-size(32), 2::little-size(16), 1::little-size(32),
                 2::little-size(32), 3::little-size(32), 4::little-size(32)>>
    end
  end
end
