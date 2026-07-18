defmodule ThistleTea.Game.World.Loader.TalentTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Talent, as: TalentData
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

  test "multi-rank talents list every rank in order" do
    assert %TalentData{rank_spell_ids: [12_285, 12_697]} = TalentLoader.get(126)
  end
end
