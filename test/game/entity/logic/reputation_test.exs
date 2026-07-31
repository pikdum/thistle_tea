defmodule ThistleTea.Game.Entity.Logic.ReputationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.Spillover
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Logic.Reputation

  @human 1
  @orc 2
  @warrior 1

  describe "initialize/3" do
    test "selects the first race and class variant that fits" do
      catalog =
        catalog([
          definition(72, 19, [
            variant(race_mask: race_mask(@human), base: 3_100, flags: 0x11),
            variant(race_mask: race_mask(@orc), base: -42_000, flags: 0x06)
          ])
        ])

      human = Reputation.initialize(catalog, @human, @warrior)
      orc = Reputation.initialize(catalog, @orc, @warrior)

      assert Reputation.standing(human, catalog, 72, @human, @warrior) == 3_100
      assert Reputation.state(human, 72).flags == 0x11
      assert Reputation.standing(orc, catalog, 72, @orc, @warrior) == -42_000
      assert Reputation.state(orc, 72).flags == 0x06
    end

    test "creates all indexed factions even without a matching base variant" do
      catalog = catalog([definition(529, 13, [variant(race_mask: race_mask(@orc), base: 200)])])

      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert Reputation.state(reputation, 529).index == 13
      assert Reputation.standing(reputation, catalog, 529, @human, @warrior) == 0
    end
  end

  describe "normalize/4" do
    test "restores the mandatory at-war flag for hostile standing" do
      catalog = catalog([definition(529, 13, [variant()])])
      reputation = Reputation.initialize(catalog, @human, @warrior)
      state = %{Reputation.state(reputation, 529) | standing: -6_000, flags: 0}
      reputation = %{reputation | states: %{529 => state}}

      reputation = Reputation.normalize(reputation, catalog, @human, @warrior)

      assert Reputation.at_war?(reputation, 529)
      assert reputation.ranks[529] == :hostile
    end
  end

  describe "rank/1" do
    test "uses classic standing thresholds" do
      assert Reputation.rank(-42_000) == :hated
      assert Reputation.rank(-6_001) == :hated
      assert Reputation.rank(-6_000) == :hostile
      assert Reputation.rank(-3_000) == :unfriendly
      assert Reputation.rank(0) == :neutral
      assert Reputation.rank(3_000) == :friendly
      assert Reputation.rank(9_000) == :honored
      assert Reputation.rank(21_000) == :revered
      assert Reputation.rank(42_000) == :exalted
      assert Reputation.rank(42_999) == :exalted
    end
  end

  describe "calculate_gain/5" do
    test "dithers fractional gains and losses without applying positive bonuses to losses" do
      assert Reputation.calculate_gain(25, 1.0, 1.0, 10, fn -> 0.4 end) == 27
      assert Reputation.calculate_gain(25, 1.0, 1.0, 10, fn -> 0.6 end) == 28
      assert Reputation.calculate_gain(-25, 1.0, 1.0, 0, fn -> 0.4 end) == -25
      assert Reputation.calculate_gain(25, 0.0, 1.0, 10, fn -> 0.4 end) == 0
    end

    test "applies classic low-level quest and kill reductions only to gains" do
      assert Reputation.level_rate(:quest, 25, 60, 55) == 1.0
      assert Reputation.level_rate(:quest, 25, 60, 54) == 0.8
      assert Reputation.level_rate(:quest, 25, 60, 51) == 0.2
      assert Reputation.level_rate(:kill, 5, 60, 49) == 0.2
      assert Reputation.level_rate(:kill, -5, 60, 1) == 1.0
      assert Reputation.level_rate(:spell, 5, 60, 1) == 1.0
    end
  end

  describe "modify/6" do
    test "stores an offset from the racial base and makes the faction visible" do
      catalog = catalog([definition(72, 19, [variant(base: 3_100, flags: 0x10)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      {reputation, [change]} =
        Reputation.modify(reputation, catalog, 72, 250, context(), spillover?: false)

      assert Reputation.standing(reputation, catalog, 72, @human, @warrior) == 3_350
      assert Reputation.state(reputation, 72).standing == 250
      assert change.standing == 250
      assert Bitwise.band(change.flags, 0x01) != 0
    end

    test "clamps total standing without losing the base offset model" do
      catalog = catalog([definition(72, 19, [variant(base: 3_100)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      {reputation, _changes} = Reputation.modify(reputation, catalog, 72, 100_000, context())

      assert Reputation.standing(reputation, catalog, 72, @human, @warrior) == 42_999
      assert Reputation.state(reputation, 72).standing == 39_899
    end

    test "forces at-war when standing becomes hostile" do
      catalog = catalog([definition(87, 0, [variant(base: -5_900)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      {reputation, _changes} = Reputation.modify(reputation, catalog, 87, -100, context())

      assert Reputation.at_war?(reputation, 87)
      assert Reputation.hostile?(reputation, catalog, 87, context())
    end

    test "keeps hidden and forced-invisible factions invisible" do
      catalog =
        catalog([
          definition(1, 0, [variant(flags: 0x04)]),
          definition(2, 1, [variant(flags: 0x08)])
        ])

      reputation = Reputation.initialize(catalog, @human, @warrior)
      {reputation, changes} = Reputation.modify(reputation, catalog, 1, 10, context())
      {reputation, more_changes} = Reputation.modify(reputation, catalog, 2, 10, context())

      refute Enum.any?(changes ++ more_changes, &(Bitwise.band(&1.flags, 0x01) != 0))
      refute Reputation.visible?(Reputation.state(reputation, 1))
      refute Reputation.visible?(Reputation.state(reputation, 2))
    end

    test "applies configured spillover while the target rank is within its cap" do
      catalog =
        catalog(
          [
            definition(469, 11, [variant()]),
            definition(72, 19, [variant()])
          ],
          %{469 => [%Spillover{faction_id: 72, rate: 0.25, max_rank: 7}]}
        )

      reputation = Reputation.initialize(catalog, @human, @warrior)
      {reputation, changes} = Reputation.modify(reputation, catalog, 469, 100, context())

      assert Enum.map(changes, &{&1.faction_id, &1.standing}) == [{72, 25}, {469, 100}]
      assert Reputation.standing(reputation, catalog, 72, @human, @warrior) == 25
    end

    test "skips spillover above its configured rank cap" do
      catalog =
        catalog(
          [
            definition(469, 11, [variant()]),
            definition(72, 19, [variant(base: 3_000)])
          ],
          %{469 => [%Spillover{faction_id: 72, rate: 0.25, max_rank: 3}]}
        )

      reputation = Reputation.initialize(catalog, @human, @warrior)
      {_reputation, changes} = Reputation.modify(reputation, catalog, 469, 100, context())

      assert Enum.map(changes, & &1.faction_id) == [469]
    end
  end

  describe "set/5" do
    test "sets an absolute total standing" do
      catalog = catalog([definition(72, 19, [variant(base: 3_100)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      {reputation, _changes} = Reputation.set(reputation, catalog, 72, 9_000, context())

      assert Reputation.standing(reputation, catalog, 72, @human, @warrior) == 9_000
      assert Reputation.state(reputation, 72).standing == 5_900
    end
  end

  describe "meets_requirement?/5" do
    test "compares current and required ranks for a known faction" do
      catalog = catalog([definition(529, 13, [variant(base: 3_000)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert Reputation.meets_requirement?(reputation, catalog, 529, :friendly, context())
      assert Reputation.meets_requirement?(reputation, catalog, 529, 4, context())
      refute Reputation.meets_requirement?(reputation, catalog, 529, :honored, context())
      refute Reputation.meets_requirement?(reputation, catalog, 999, :neutral, context())
    end
  end

  describe "set_visible/2" do
    test "reveals an ordinary faction but not hidden or forced-invisible factions" do
      catalog =
        catalog([
          definition(1, 0, [variant()]),
          definition(2, 1, [variant(flags: 0x04)]),
          definition(3, 2, [variant(flags: 0x08)])
        ])

      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert {:ok, reputation, change} = Reputation.set_visible(reputation, 1)
      assert Reputation.visible?(Reputation.state(reputation, 1))
      assert Bitwise.band(change.flags, 0x01) != 0
      assert {:error, :not_allowed} = Reputation.set_visible(reputation, 2)
      assert {:error, :not_allowed} = Reputation.set_visible(reputation, 3)
    end
  end

  describe "set_at_war/5" do
    test "toggles a visible faction by reputation-list index" do
      catalog = catalog([definition(72, 19, [variant(flags: 0x01)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert {:ok, reputation, change} = Reputation.set_at_war(reputation, catalog, 19, true, context())
      assert Reputation.at_war?(reputation, 72)
      assert Bitwise.band(change.flags, 0x02) != 0
      assert {:error, :not_allowed} = Reputation.set_at_war(reputation, catalog, 19, true, context())

      assert {:ok, reputation, _change} = Reputation.set_at_war(reputation, catalog, 19, false, context())
      refute Reputation.at_war?(reputation, 72)
    end

    test "rejects hidden factions and peace-forced factions above hated" do
      catalog =
        catalog([
          definition(1, 0, [variant(flags: 0x04)]),
          definition(2, 1, [variant(flags: 0x11)])
        ])

      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert {:error, :not_allowed} = Reputation.set_at_war(reputation, catalog, 0, true, context())
      assert {:error, :not_allowed} = Reputation.set_at_war(reputation, catalog, 1, true, context())
    end
  end

  describe "temporary at-war lifecycle" do
    test "marks a neutral attacking faction and clears it after combat" do
      catalog = catalog([definition(529, 13, [variant(flags: 0x01)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert {:ok, reputation, change} = Reputation.set_temporary_at_war(reputation, 529)
      assert change.index == 13
      assert Reputation.at_war?(reputation, 529)
      assert reputation.temporary_at_war == MapSet.new([529])

      assert {reputation, [change]} = Reputation.clear_temporary_at_war(reputation)
      refute Reputation.at_war?(reputation, 529)
      assert change.index == 13
      assert reputation.temporary_at_war == MapSet.new()
    end

    test "keeps a temporarily hostile faction at war when combat ends" do
      catalog = catalog([definition(529, 13, [variant(flags: 0x01)])])
      reputation = Reputation.initialize(catalog, @human, @warrior)
      {:ok, reputation, _change} = Reputation.set_temporary_at_war(reputation, 529)
      {reputation, _changes} = Reputation.modify(reputation, catalog, 529, -6_000, context())

      assert {reputation, []} = Reputation.clear_temporary_at_war(reputation)
      assert Reputation.at_war?(reputation, 529)
      assert reputation.temporary_at_war == MapSet.new()
    end

    test "does not mark hidden, peace-forced, or already at-war factions as temporary" do
      catalog =
        catalog([
          definition(1, 0, [variant(flags: 0x04)]),
          definition(2, 1, [variant(flags: 0x10)]),
          definition(3, 2, [variant(flags: 0x02)])
        ])

      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert {:error, :not_allowed} = Reputation.set_temporary_at_war(reputation, 1)
      assert {:error, :not_allowed} = Reputation.set_temporary_at_war(reputation, 2)
      assert {:error, :not_allowed} = Reputation.set_temporary_at_war(reputation, 3)
      assert reputation.temporary_at_war == MapSet.new()
    end
  end

  describe "set_inactive/3" do
    test "requires visibility when enabling and permits disabling" do
      catalog =
        catalog([
          definition(1, 0, [variant(flags: 0)]),
          definition(2, 1, [variant(flags: 0x21)])
        ])

      reputation = Reputation.initialize(catalog, @human, @warrior)

      assert {:error, :not_allowed} = Reputation.set_inactive(reputation, 0, true)
      assert {:ok, reputation, _change} = Reputation.set_inactive(reputation, 1, false)
      refute Reputation.inactive?(Reputation.state(reputation, 2))
    end
  end

  defp catalog(definitions, spillovers \\ %{}) do
    %Catalog{factions: Map.new(definitions, &{&1.id, &1}), spillovers: spillovers}
  end

  defp definition(id, index, variants) do
    %Definition{id: id, index: index, name: "Faction #{id}", variants: variants}
  end

  defp variant(opts \\ []) do
    %Variant{
      race_mask: Keyword.get(opts, :race_mask, 0),
      class_mask: Keyword.get(opts, :class_mask, 0),
      base_standing: Keyword.get(opts, :base, 0),
      flags: Keyword.get(opts, :flags, 0)
    }
  end

  defp race_mask(race), do: Bitwise.bsl(1, race - 1)
  defp context, do: %{race: @human, class: @warrior}
end
