defmodule ThistleTea.Game.World.Loader.SpellLinkedAuraDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos.SpellEffectMod
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:barkskin_link]

  describe "load/1" do
    test "loads Barkskin's linked physical protection and melee penalty" do
      barkskin = SpellLoader.load(22_812)
      assert Enum.any?(barkskin.effects, &match?(%Effect{aura: :linked_aura, trigger_spell_id: 22_839}, &1))
      assert [child] = barkskin.linked_auras
      assert child.id == 22_839
      assert child.duration_ms == 15_000

      assert [%Effect{aura: :mod_melee_haste} = haste, %Effect{aura: :mod_damage_percent_taken} = protection] =
               child.effects

      assert Effect.roll(haste, 0) == -25
      assert Effect.roll(protection, 0) == -20
      assert protection.misc_value == 1
    end

    test "cuts cycles while retaining the linked spell's ordinary effects" do
      insert_link(22_839, 22_812)
      assert [child] = SpellLoader.load(22_812).linked_auras
      assert child.linked_auras == []
      assert Enum.any?(child.effects, &(&1.aura == :mod_melee_haste))
    end

    test "ignores missing linked definitions" do
      insert_link(22_812, 999_999)
      assert SpellLoader.load(22_812).linked_auras == []
    end
  end

  describe "build_spellbook/1" do
    test "retains the same links as individual loading" do
      assert SpellLoader.build_spellbook([22_812])[22_812] == SpellLoader.load(22_812)
    end
  end

  defp barkskin_link(_context), do: insert_link(22_812, 22_839)

  defp insert_link(id, child) do
    key = {:mods, id}
    previous = :ets.lookup(SpellEffectOverride, key)
    mod = %SpellEffectMod{id: id, effect_index: 1, effect: 6, effect_apply_aura_name: 192, effect_trigger_spell: child}
    :ets.insert(SpellEffectOverride, {key, %{1 => mod}})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
