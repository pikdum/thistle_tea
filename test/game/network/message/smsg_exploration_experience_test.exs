defmodule ThistleTea.Game.Network.Message.SmsgExplorationExperienceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgExplorationExperience

  describe "to_binary/1" do
    test "encodes the area and experience" do
      message = %SmsgExplorationExperience{area_id: 1637, experience: 55}

      assert SmsgExplorationExperience.to_binary(message) == <<1637::little-size(32), 55::little-size(32)>>
    end
  end
end
