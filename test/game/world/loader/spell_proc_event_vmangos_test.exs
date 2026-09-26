defmodule ThistleTea.Game.World.Loader.SpellProcEventVmangosTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Loader.SpellScriptName
  alias ThistleTea.Game.World.Loader.SpellThreat

  @moduletag :vmangos_db

  setup do
    SpellProcEvent.init()
    SpellProcEvent.load_all()
    :ok
  end

  describe "get/1" do
    test "depleting trinkets use their dummy scripts and unmodified DBC proc flags" do
      SpellScriptName.init()
      SpellScriptName.load_all()
      assert SpellScriptName.get(29_284) == "spell_brittle_armor_dummy"
      assert SpellScriptName.get(29_286) == "spell_mercurial_shield_dummy"

      for id <- [24_661, 24_574, 26_463] do
        assert SpellProcEvent.get(id) == nil
      end
    end

    test "ranged equipment procs use their supported-build PPM rates" do
      for {id, rate} <- [{23_578, 2.0}, {26_480, 10.0}] do
        assert %ProcRule{ppm_rate: ^rate, custom_chance: chance} = SpellProcEvent.get(id)
        assert chance == 0.0
      end
    end

    test "healing set procs restrict their triggering spell families" do
      assert %ProcRule{spell_family: 10, family_mask_0: 0xC0006000, proc_flags: 0, proc_ex: 0} =
               SpellProcEvent.get(28_789)

      assert %ProcRule{spell_family: 0, family_mask_0: 0xC0, proc_flags: 0, proc_ex: 0} =
               SpellProcEvent.get(28_823)
    end

    test "Shadowguard ranks share an absorb-capable cooldown and cause no damage threat" do
      assert %ProcRule{proc_ex: 0x403, cooldown_ms: 3_500} = SpellProcEvent.get(18_137)
      SpellThreat.init()
      SpellThreat.load_all()

      for {id, trigger} <- [
            {18_137, 28_377},
            {19_308, 28_378},
            {19_309, 28_379},
            {19_310, 28_380},
            {19_311, 28_381},
            {19_312, 28_382}
          ] do
        assert %{first_spell: 18_137} = Mangos.Repo.get_by(Mangos.SpellChain, spell_id: id)
        assert SpellThreat.get(trigger) == %{threat: 0.0, multiplier: 0.0}
      end
    end

    test "Blessed Recovery inherits its critical-only restriction from the first talent rank" do
      assert %ProcRule{proc_ex: 2, proc_flags: 0} = SpellProcEvent.get(27_811)

      for id <- [27_815, 27_816] do
        assert Mangos.Repo.get_by(Mangos.SpellProcEvent, entry: id) == nil
      end

      for id <- [27_813, 27_817, 27_818, 26_470] do
        template =
          Mangos.Repo.one(
            from(s in Mangos.SpellTemplate,
              where: s.entry == ^id and s.build <= 5875,
              order_by: [desc: s.build],
              limit: 1
            )
          )

        assert template.effect_bonus_coefficient_0 == 0.0
      end
    end

    test "Deep Wounds stores its critical-only rule on the first talent rank" do
      assert %ProcRule{proc_ex: 2} = SpellProcEvent.get(12_834)

      for id <- [12_849, 12_867] do
        assert Mangos.Repo.get_by(Mangos.SpellProcEvent, entry: id) == nil
      end
    end

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
      assert %ProcRule{family_mask_0: 96, family_mask_1: 128, proc_flags: 0x50400, custom_chance: chance} =
               SpellProcEvent.get(18_096)

      assert chance == 0.0
      assert Mangos.Repo.get_by(Mangos.SpellProcEvent, entry: 18_073) == nil
    end
  end
end
