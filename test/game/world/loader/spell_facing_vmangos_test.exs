defmodule ThistleTea.Game.World.Loader.SpellFacingVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "retains authored facing requirements instead of inferring from hostility" do
      SpellEffectOverride.load_all()

      for id <- [75, 78, 116, 133, 403, 585, 686, 1752, 1776, 2098, 5019] do
        assert Spell.custom?(%Spell{custom_flags: SpellEffectOverride.custom_flags(id)}, :face_target), "spell #{id}"
      end

      for id <- [139, 172, 2050] do
        refute Spell.custom?(%Spell{custom_flags: SpellEffectOverride.custom_flags(id)}, :face_target), "spell #{id}"
      end
    end
  end
end
