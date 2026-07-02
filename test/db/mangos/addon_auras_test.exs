defmodule ThistleTea.DB.Mangos.AddonAurasTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.AddonAuras

  describe "parse/1" do
    test "parses space-separated spell ids" do
      assert AddonAuras.parse("12544") == [12_544]
      assert AddonAuras.parse("8279 6408") == [8_279, 6_408]
    end

    test "skips invalid tokens" do
      assert AddonAuras.parse("  8279   abc 0 -5 6408 ") == [8_279, 6_408]
    end

    test "handles missing values" do
      assert AddonAuras.parse(nil) == []
      assert AddonAuras.parse("") == []
    end
  end
end
