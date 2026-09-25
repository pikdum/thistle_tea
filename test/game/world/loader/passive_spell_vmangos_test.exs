defmodule ThistleTea.Game.World.Loader.PassiveSpellVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.PassiveSpell

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "preloads hidden Feline Swiftness dependencies without active spell grants" do
      PassiveSpell.load_all()
      assert PassiveSpell.get(17_002) == [24_867]
      assert PassiveSpell.get(24_866) == [24_864]
      assert PassiveSpell.get(2842) == []
      assert PassiveSpell.get(5149) == []
    end
  end
end
