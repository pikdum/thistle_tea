defmodule ThistleTea.Game.Core.GameEvent.ScourgeInvasion.CampTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.ScourgeInvasion.Camp
  alias ThistleTea.Game.Core.Rolls

  @spectral_soldier 16_298
  @skeletal_shocktrooper 16_299
  @spirit_of_the_damned 16_379

  defp camp(_context) do
    %{camp: Camp.new(Rolls.fixed(camp_type: 1))}
  end

  describe "new/1" do
    test "rolls the camp type" do
      assert %Camp{type: :ghost_ghoul, stage: :shard} = Camp.new(Rolls.fixed(camp_type: 0))
      assert %Camp{type: :ghoul_skeleton} = Camp.new(Rolls.fixed(camp_type: 2))
    end
  end

  describe "call/4" do
    setup [:camp]

    test "calls the nearest free finders and rests them", %{camp: camp} do
      candidates = [{1, 30.0, false}, {2, 10.0, false}, {3, 5.0, true}, {4, 20.0, false}]
      rolls = Rolls.fixed(finders: 2, finder_rest: 150_000)

      {camp, called} = Camp.call(camp, candidates, 1_000, rolls)

      assert called == [2, 4]
      assert camp.resting == %{2 => 151_000, 4 => 151_000}
    end

    test "skips finders still resting", %{camp: camp} do
      camp = %{camp | resting: %{2 => 5_000}}
      rolls = Rolls.fixed(finders: 3, finder_rest: 150_000)

      {_camp, called} = Camp.call(camp, [{1, 30.0, false}, {2, 10.0, false}], 1_000, rolls)

      assert called == [1]
    end
  end

  describe "minion_entry/2" do
    setup [:camp]

    test "picks from the camp type's pair", %{camp: camp} do
      assert Camp.minion_entry(camp, Rolls.fixed(rare_minion: 2, minion: 0)) == @spectral_soldier
      assert Camp.minion_entry(camp, Rolls.fixed(rare_minion: 2, minion: 1)) == @skeletal_shocktrooper
    end

    test "calls a rare only while the camp has none", %{camp: camp} do
      rolls = Rolls.fixed(rare_minion: 1, minion: 0)

      assert Camp.minion_entry(camp, rolls) == @spirit_of_the_damned

      camp = Camp.summoned(camp, 9, @spirit_of_the_damned)
      assert Camp.minion_entry(camp, rolls) == @spectral_soldier
    end
  end

  describe "died/3" do
    setup [:camp]

    test "breaks the shard, then loses the camp with the damaged shard", %{camp: camp} do
      camp = Camp.summoned(camp, 1, Camp.shard())

      assert {%Camp{stage: :damaged, shard: nil} = camp, :shard_fell} = Camp.died(camp, 1, Camp.shard())

      camp = Camp.summoned(camp, 2, Camp.damaged_shard())
      assert camp.shard == 2

      assert {%Camp{stage: :fallen}, :camp_fell} = Camp.died(camp, 2, Camp.damaged_shard())
    end

    test "strikes the damaged shard only for its own cultists", %{camp: camp} do
      camp = %{camp | stage: :damaged} |> Camp.summoned(5, Camp.cultist())

      assert {%Camp{cultists: cultists}, :cultist_fell} = Camp.died(camp, 5, Camp.cultist())
      assert MapSet.size(cultists) == 0
      assert {_camp, nil} = Camp.died(camp, 6, Camp.cultist())
    end

    test "forgets slain minions", %{camp: camp} do
      camp = Camp.summoned(camp, 7, @spectral_soldier)

      assert {%Camp{minions: minions}, nil} = Camp.died(camp, 7, @spectral_soldier)
      assert MapSet.size(minions) == 0
    end
  end

  describe "despawned/3" do
    setup [:camp]

    test "frees the rare slot", %{camp: camp} do
      camp = Camp.summoned(camp, 9, @spirit_of_the_damned)

      assert %Camp{rares: rares, minions: minions} = Camp.despawned(camp, 9, @spirit_of_the_damned)
      assert MapSet.size(rares) == 0
      assert MapSet.size(minions) == 0
    end
  end

  describe "spawning?/1" do
    test "stops once the camp falls" do
      assert Camp.spawning?(%Camp{stage: :damaged})
      refute Camp.spawning?(%Camp{stage: :fallen})
    end
  end

  describe "cultist_positions/1" do
    test "rings four cultists facing the shard" do
      [{x, y, z, o} | _] = positions = Camp.cultist_positions({100.0, 200.0, 5.0, 0.0})

      assert length(positions) == 4
      assert_in_delta x, 106.95, 0.001
      assert_in_delta y, 200.0, 0.001
      assert z == 5.0
      assert_in_delta o, -:math.pi(), 0.001
    end
  end
end
