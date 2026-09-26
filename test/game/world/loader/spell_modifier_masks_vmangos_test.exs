defmodule ThistleTea.Game.World.Loader.SpellModifierMasksVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads target-trigger restrictions for Revealed Flaw and Shadow Weaving" do
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.class_mask(28_814, 0) == 0x20000
      assert SpellEffectOverride.class_mask(15_334, 0) == 42_508_288
    end

    test "loads Plagueheart's periodic threat mask including its high bit" do
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.class_mask(28_746, 1) == 4_294_968_326
    end

    test "loads Cannibalize damage interruption from spell_mod" do
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.aura_interrupt_flags(20_578, 0) == 2
      assert SpellEffectOverride.aura_interrupt_flags(999_999, 16) == 16
    end

    test "keeps original aura interrupt flags for sentinel overrides" do
      SpellEffectOverride.load_all()

      assert SpellEffectOverride.aura_interrupt_flags(543, 16) == 16
      assert :ets.lookup(SpellEffectOverride, {:aura_interrupt_flags, 543}) == []
    end

    test "retains explicit zero aura interrupt flags" do
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.aura_interrupt_flags(24_322, 16) == 0
    end

    test "loads vanilla Vile Poisons masks from the latest supported build" do
      SpellEffectOverride.load_all()

      assert SpellEffectOverride.class_mask(16_720, 0) == 73_728
      assert SpellEffectOverride.class_mask(16_720, 1) == 65_536
      assert SpellEffectOverride.class_mask(16_720, 2) == 268_550_144

      assert SpellEffectOverride.class_mask(999_999, 0) == nil
    end
  end
end
