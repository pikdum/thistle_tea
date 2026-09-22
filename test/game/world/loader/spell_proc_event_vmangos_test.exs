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
    test "stacking spell trinkets trigger at cast completion" do
      for id <- [24_659, 28_200] do
        assert %ProcRule{proc_ex: 0x80000} = SpellProcEvent.get(id)
      end
    end

    test "loads cast-completion restrictions for Elemental Focus and Blue Dragon" do
      assert %ProcRule{proc_ex: 0x80000, school_mask: 28, spell_family: 11, proc_flags: 0x10000} =
               SpellProcEvent.get(16_164)

      assert %ProcRule{proc_ex: 0x80000} = SpellProcEvent.get(23_688)
    end

    test "loads Heart of Wyrmthalak physical-school PPM restriction" do
      assert %ProcRule{school_mask: 1, ppm_rate: 1.0} = SpellProcEvent.get(27_656)
    end

    test "loads the guaranteed first reflection restriction" do
      assert %ProcRule{proc_ex: 0x800} = SpellProcEvent.get(30_003)
    end

    test "loads Combustion's fire-only rule for the supported build" do
      assert %ProcRule{school_mask: 4} = SpellProcEvent.get(11_129)
    end

    test "splits VMangos combined family masks into the two vanilla words" do
      assert %ProcRule{family_mask_0: 96, family_mask_1: 128} = SpellProcEvent.get(18_096)
    end
  end
end
