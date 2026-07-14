defmodule ThistleTeaWeb.HomographyTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ThistleTeaWeb.Homography

  describe "transform/2" do
    test "maps Eastern Kingdoms world coordinates to image coordinates" do
      {x, y} = Homography.transform({-8913.14, -137.78}, 0)

      assert_in_delta x, 9315.150390625, 1.0e-3
      assert_in_delta y, 3893.0400390625, 1.0e-3
    end

    test "maps Kalimdor world coordinates to image coordinates" do
      {x, y} = Homography.transform({7981.32, -2576.5}, 1)

      assert_in_delta x, 3313.443576491074, 1.0e-3
      assert_in_delta y, 8667.170364825663, 1.0e-3
    end
  end
end
