defmodule ThistleTea.Game.World.Loader.TalentTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData
  alias ThistleTea.Game.Entity.Logic.Talents
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  @moduletag :dbc_db

  setup_all do
    TalentLoader.init()
    :ok = TalentLoader.load_all()
  end

  test "classes get their three talent tabs" do
    assert length(TalentLoader.tab_ids(1)) == 3
    assert length(TalentLoader.tab_ids(8)) == 3
    assert TalentLoader.tab_ids(6) == []
  end

  test "mortal strike loads as a deep arms talent with its rank spell" do
    assert %TalentData{tier: 6, rank_spell_ids: [12_294]} = TalentLoader.get(135)
  end

  test "the reverse index maps rank spells back to talent and rank" do
    %TalentData{tab_id: tab_id} = TalentLoader.get(135)

    assert TalentLoader.by_spell(12_294) == {135, tab_id, 0}
  end

  test "trained successors retain their talent identity and lineage" do
    %TalentData{tab_id: tab_id} = TalentLoader.get(135)

    assert TalentLoader.by_spell(21_551) == {135, tab_id, 0}
    assert TalentLoader.by_spell(21_553) == {135, tab_id, 0}

    assert TalentLoader.chain(21_551) == %{
             first_spell: 12_294,
             prev_spell: 12_294,
             rank: 2,
             req_spell: nil
           }

    assert Talents.known_talent_spell_ids([21_553]) == [21_553]
  end

  test "talent ranks form a replacement chain" do
    assert TalentLoader.superseded_by_map([12_282, 12_663, 12_664]) == %{
             12_282 => 12_663,
             12_663 => 12_664
           }
  end

  test "talent learn-spell effects expose their dependent abilities" do
    assert TalentLoader.dependent_spell_ids(16_268) == [18_848]
    assert TalentLoader.dependent_spell_ids(16_269) == [197, 199]
  end

  test "multi-rank talents list every rank in order" do
    assert %TalentData{rank_spell_ids: [12_285, 12_697]} = TalentLoader.get(126)
  end
end
