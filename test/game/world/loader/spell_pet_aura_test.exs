defmodule ThistleTea.Game.World.Loader.SpellPetAuraTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.SpellPetAura

  describe "pet_aura_ids/2" do
    setup do
      SpellPetAura.init()
      :ets.insert(SpellPetAura, {19_028, [{0, 25_228}]})
      :ets.insert(SpellPetAura, {23_785, [{416, 23_759}, {417, 23_762}]})
      :ok
    end

    test "matches any pet when the link's pet entry is zero" do
      assert SpellPetAura.pet_aura_ids(19_028, 12_345) == [25_228]
    end

    test "filters entry-specific links to the active pet" do
      assert SpellPetAura.pet_aura_ids(23_785, 416) == [23_759]
      assert SpellPetAura.pet_aura_ids(23_785, 417) == [23_762]
      assert SpellPetAura.pet_aura_ids(23_785, 999) == []
    end

    test "returns an empty list for spells without links" do
      assert SpellPetAura.pet_aura_ids(1, 416) == []
    end
  end
end
