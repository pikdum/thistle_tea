defmodule ThistleTea.Game.World.Loader.ReputationDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DBC
  alias ThistleTea.Game.World.Loader.Reputation

  @moduletag :dbc_db

  describe "build_catalog/4" do
    test "translates all indexed DBC factions and signed base standings" do
      catalog = Reputation.build_catalog(DBC.all(Faction), [], [], [])

      assert map_size(catalog.factions) == 54
      assert catalog.factions[87].name == "Bloodsail Buccaneers"
      assert catalog.factions[87].index == 0
      assert hd(catalog.factions[87].variants).base_standing == -6_500
      refute Map.has_key?(catalog.factions, 1)
    end
  end
end
