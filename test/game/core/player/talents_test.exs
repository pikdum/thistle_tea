defmodule ThistleTea.Game.Core.Player.TalentsTest.Catalog do
  @moduledoc false
  @behaviour ThistleTea.Game.Core.Player.TalentCatalog

  alias ThistleTea.Game.Core.Player.Talent

  @warrior_tab 161

  @talents [
    %Talent{id: 100, tab_id: @warrior_tab, tier: 0, column: 0, rank_spell_ids: [1_001, 1_002, 1_003]},
    %Talent{id: 101, tab_id: @warrior_tab, tier: 1, column: 0, rank_spell_ids: [2_001]},
    %Talent{
      id: 102,
      tab_id: @warrior_tab,
      tier: 1,
      column: 1,
      depends_on: 100,
      depends_on_rank: 2,
      rank_spell_ids: [3_001]
    },
    %Talent{id: 103, tab_id: @warrior_tab, tier: 0, column: 1, rank_spell_ids: [5_001, 5_002, 5_003]},
    %Talent{id: 200, tab_id: 999, tier: 0, column: 0, rank_spell_ids: [4_001]}
  ]

  @impl true
  def get(talent_id), do: Enum.find(@talents, &(&1.id == talent_id))

  @impl true
  def tab_ids(1), do: [@warrior_tab]
  def tab_ids(_class), do: []

  @impl true
  def by_spell(spell_id) do
    Enum.find_value(@talents, fn talent ->
      case Enum.find_index(talent.rank_spell_ids, &(&1 == spell_id)) do
        nil -> nil
        rank_index -> {talent.id, talent.tab_id, rank_index}
      end
    end)
  end
end

defmodule ThistleTea.Game.Core.Player.TalentsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Player.Talents
  alias ThistleTea.Game.Core.Player.TalentsTest.Catalog

  defp warrior(level, spells) do
    %Character{
      unit: %Unit{class: 1, level: level},
      player: %Player{},
      internal: %Internal{spells: spells}
    }
  end

  describe "points" do
    test "one point per level starting at ten" do
      assert Talents.total_points(9) == 0
      assert Talents.total_points(10) == 1
      assert Talents.total_points(60) == 51
    end

    test "spent points derive from the highest known rank per talent" do
      assert Talents.spent_points([1_002, 2_001], Catalog) == 3
      assert Talents.spent_points([1_001, 1_002], Catalog) == 2
      assert Talents.spent_points([9_999], Catalog) == 0
    end

    test "sync_points writes the unspent total to the character points field" do
      character = Talents.sync_points(warrior(12, [1_001]), Catalog)

      assert character.player.character_points1 == 2
    end
  end

  describe "validate/3" do
    test "learns the next rank when a point is available" do
      assert {:ok, [1_001]} = Talents.validate(warrior(10, []), 100, 0, Catalog)
      assert {:ok, [1_002]} = Talents.validate(warrior(12, [1_001]), 100, 1, Catalog)
    end

    test "rejects skipping ranks without enough points and allows paid jumps" do
      assert :error = Talents.validate(warrior(10, []), 100, 1, Catalog)
      assert {:ok, [1_001, 1_002]} = Talents.validate(warrior(11, []), 100, 1, Catalog)
    end

    test "rejects already-known ranks, other classes' talents, and no points" do
      assert :error = Talents.validate(warrior(12, [1_001]), 100, 0, Catalog)
      assert :error = Talents.validate(warrior(60, []), 200, 0, Catalog)
      assert :error = Talents.validate(warrior(9, []), 100, 0, Catalog)
    end

    test "enforces the five-points-per-tier gate" do
      assert :error = Talents.validate(warrior(20, [1_003]), 101, 0, Catalog)
      assert :error = Talents.validate(warrior(20, [1_003, 5_001]), 101, 0, Catalog)
      assert {:ok, [2_001]} = Talents.validate(warrior(20, [1_003, 5_002]), 101, 0, Catalog)
    end

    test "enforces talent prerequisites at the required rank" do
      assert :error = Talents.validate(warrior(20, [1_002, 5_003]), 102, 0, Catalog)
      assert {:ok, [3_001]} = Talents.validate(warrior(20, [1_003, 5_002]), 102, 0, Catalog)
    end
  end
end
