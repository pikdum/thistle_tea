defmodule ThistleTea.Game.World.Loader.SpellProcEventVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.SpellProcEvent

  @moduletag :vmangos_db

  setup do
    SpellProcEvent.init()
    SpellProcEvent.load_all()
    :ok
  end

  describe "get/1" do
    test "loads Combustion's fire-only rule for the supported build" do
      assert %ProcRule{school_mask: 4} = SpellProcEvent.get(11_129)
    end

    test "splits VMangos combined family masks into the two vanilla words" do
      assert %ProcRule{family_mask_0: 96, family_mask_1: 128} = SpellProcEvent.get(18_096)
    end
  end
end
