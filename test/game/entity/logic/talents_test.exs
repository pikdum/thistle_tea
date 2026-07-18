defmodule ThistleTea.Game.Entity.Logic.TalentsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData
  alias ThistleTea.Game.Entity.Logic.Talents
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  @warrior_tab 161

  setup do
    TalentLoader.init()

    talents = [
      %TalentData{id: 100, tab_id: @warrior_tab, tier: 0, column: 0, rank_spell_ids: [1_001, 1_002, 1_003]},
      %TalentData{id: 101, tab_id: @warrior_tab, tier: 1, column: 0, rank_spell_ids: [2_001]},
      %TalentData{
        id: 102,
        tab_id: @warrior_tab,
        tier: 1,
        column: 1,
        depends_on: 100,
        depends_on_rank: 2,
        rank_spell_ids: [3_001]
      },
      %TalentData{id: 103, tab_id: @warrior_tab, tier: 0, column: 1, rank_spell_ids: [5_001, 5_002, 5_003]},
      %TalentData{id: 200, tab_id: 999, tier: 0, column: 0, rank_spell_ids: [4_001]}
    ]

    Enum.each(talents, fn talent ->
      :ets.insert(TalentLoader, {{:talent, talent.id}, talent})

      talent.rank_spell_ids
      |> Enum.with_index()
      |> Enum.each(fn {spell_id, rank_index} ->
        :ets.insert(TalentLoader, {{:by_spell, spell_id}, {talent.id, talent.tab_id, rank_index}})
      end)
    end)

    :ets.insert(TalentLoader, {{:tabs, 1}, [@warrior_tab]})

    on_exit(fn ->
      if :ets.whereis(TalentLoader) != :undefined, do: :ets.delete_all_objects(TalentLoader)
    end)

    :ok
  end

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
      assert Talents.spent_points([1_002, 2_001]) == 3
      assert Talents.spent_points([1_001, 1_002]) == 2
      assert Talents.spent_points([9_999]) == 0
    end

    test "sync_points writes the unspent total to the character points field" do
      character = Talents.sync_points(warrior(12, [1_001]))

      assert character.player.character_points1 == 2
    end
  end

  describe "validate/3" do
    test "learns the next rank when a point is available" do
      assert {:ok, 1_001} = Talents.validate(warrior(10, []), 100, 0)
      assert {:ok, 1_002} = Talents.validate(warrior(12, [1_001]), 100, 1)
    end

    test "rejects skipping ranks without enough points and allows paid jumps" do
      assert :error = Talents.validate(warrior(10, []), 100, 1)
      assert {:ok, 1_002} = Talents.validate(warrior(11, []), 100, 1)
    end

    test "rejects already-known ranks, other classes' talents, and no points" do
      assert :error = Talents.validate(warrior(12, [1_001]), 100, 0)
      assert :error = Talents.validate(warrior(60, []), 200, 0)
      assert :error = Talents.validate(warrior(9, []), 100, 0)
    end

    test "enforces the five-points-per-tier gate" do
      assert :error = Talents.validate(warrior(20, [1_003]), 101, 0)
      assert {:ok, 2_001} = Talents.validate(warrior(20, [1_003, 5_002]), 101, 0)
    end

    test "enforces talent prerequisites at the required rank" do
      assert :error = Talents.validate(warrior(20, [1_002, 5_003]), 102, 0)
      assert {:ok, 3_001} = Talents.validate(warrior(20, [1_003, 5_002]), 102, 0)
    end
  end
end
