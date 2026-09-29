defmodule ThistleTea.Game.World.Loader.FirstAidVmangosTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Scripts

  @moduletag :vmangos_db

  describe "apply_trigger/1" do
    test "every reference bandage script grants Recently Bandaged" do
      ids =
        Mangos.Repo.all(
          from(s in Mangos.SpellTemplate,
            where: s.build <= 5875 and s.script_name == "spell_first_aid",
            select: s.entry,
            distinct: true
          )
        )

      assert 746 in ids
      assert 18_610 in ids
      assert 24_414 in ids

      for id <- ids do
        assert Scripts.apply_trigger(%Spell{id: id, script_name: "spell_first_aid"}) == 11_196
      end
    end
  end
end
