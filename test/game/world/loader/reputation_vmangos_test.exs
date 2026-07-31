defmodule ThistleTea.Game.World.Loader.ReputationVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.Reputation

  @moduletag :vmangos_db

  describe "build_catalog/4" do
    test "translates spillover and creature kill reward tables" do
      catalog =
        Reputation.build_catalog(
          [],
          Mangos.Repo.all(Mangos.ReputationSpilloverTemplate),
          Mangos.Repo.all(Mangos.CreatureOnkillReputation),
          Mangos.Repo.all(Mangos.ReputationRewardRate)
        )

      assert length(catalog.spillovers[469]) == 4

      assert Enum.map(catalog.spillovers[469], &{&1.faction_id, &1.rate}) ==
               [{47, 0.25}, {54, 0.25}, {69, 0.25}, {72, 0.25}]

      assert [%{faction_id: 21, value: 5, max_rank: 5, team: :both}] = catalog.kill_rewards[674]
      assert [%{faction_id: 471, value: 5, team: :alliance}] = catalog.kill_rewards[2552]
    end
  end
end
