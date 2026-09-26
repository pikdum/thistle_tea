defmodule ThistleTea.Game.World.Loader.SpellProcEventVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.SpellProcEvent

  @moduletag :vmangos_db

  setup do
    SpellProcEvent.init()
    SpellProcEvent.load_all()
    :ok
  end

  describe "get/1" do
    test "class-script procs retain their spell-family and periodic restrictions" do
      for {id, family, mask, flags, outcome, chance} <- [
            {11_185, 3, 0x80, 0x50000, 0, 0.0},
            {18_094, 5, 0xA, 0x40000, 0, 0.0},
            {19_572, 9, 0x800000, 0x40000, 0x40000, 0.0},
            {23_401, 6, 0, 0x4000, 0, 100.0},
            {28_716, 7, 0x10, 0x48000, 0x40000, 50.0},
            {28_744, 7, 0x40, 0x44000, 0x40003, 0.0}
          ] do
        assert %ProcRule{
                 spell_family: ^family,
                 family_mask_0: ^mask,
                 proc_flags: ^flags,
                 proc_ex: ^outcome,
                 custom_chance: ^chance
               } = SpellProcEvent.get(id)
      end
    end

    test "Shield Block spends charges only on blocked attacks" do
      assert %ProcRule{proc_ex: 0x40} = SpellProcEvent.get(2565)
    end

    test "shield spikes and first-rank Paladin defenses are block-only procs" do
      for id <- [9782, 9784, 16_624, 20_911, 20_925] do
        assert %ProcRule{proc_ex: 0x40} = SpellProcEvent.get(id)
      end

      for {id, first, rank} <- [{20_928, 20_925, 3}, {20_914, 20_911, 4}] do
        assert %{rank: ^rank} = Mangos.Repo.get_by(Mangos.SpellChain, spell_id: id, first_spell: first)
        assert Mangos.Repo.get_by(Mangos.SpellProcEvent, entry: id) == nil
      end
    end

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
