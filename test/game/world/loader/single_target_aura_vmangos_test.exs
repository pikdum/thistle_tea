defmodule ThistleTea.Game.World.Loader.SingleTargetAuraVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads caster limits for crowd control, Hunter's Mark, and judgements" do
      SpellEffectOverride.load_all()

      for id <- [
            118,
            12_826,
            28_271,
            28_272,
            1130,
            14_325,
            5782,
            6215,
            710,
            18_647,
            339,
            9853,
            2637,
            18_658,
            20_184,
            20_185,
            20_186
          ] do
        assert Spell.custom?(%Spell{custom_flags: SpellEffectOverride.custom_flags(id)}, :single_target_aura),
               "spell #{id}"
      end

      refute Spell.custom?(%Spell{custom_flags: SpellEffectOverride.custom_flags(172)}, :single_target_aura)
    end
  end
end
