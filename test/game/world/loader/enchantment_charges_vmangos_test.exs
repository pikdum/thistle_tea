defmodule ThistleTea.Game.World.Loader.EnchantmentChargesVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.ItemEnchantment

  @moduletag :vmangos_db

  describe "load_charges/0" do
    test "caches poison ranks and leaves uncharged imbues unlimited" do
      ItemEnchantment.load_charges()

      for {spell_id, charges} <- [{8679, 40}, {2823, 60}, {5761, 50}, {13_227, 105}, {25_351, 120}] do
        assert ItemEnchantment.charges(spell_id) == charges
      end

      assert ItemEnchantment.charges(8232) == 0
      assert ItemEnchantment.charges(8024) == 0
      assert Mangos.Repo.get_by!(Mangos.SpellTemplate, entry: 14_117, build: 5875).effect_item_type_0 == 268_558_336
    end
  end
end
