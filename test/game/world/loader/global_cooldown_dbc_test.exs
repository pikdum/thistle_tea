defmodule ThistleTea.Game.World.Loader.GlobalCooldownDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:caster]

  describe "load/1" do
    test "the item set bonuses reduce their own spell's cast time and global cooldown", %{caster: caster} do
      for {bonus_id, spell_id, expected_cast, expected_gcd} <- [
            {21_973, 10_917, 1400, 1400},
            {23_047, 11_668, 1800, 1300}
          ] do
        bonus = SpellLoader.load(bonus_id)
        {modified, events} = Aura.apply_spell(caster, 1, 60, bonus, 0)
        spell = SpellLoader.load(spell_id)
        assert spell.gcd_category == 133
        assert Cooldowns.gcd_duration(modified, spell) == expected_gcd
        assert Modifiers.integer_value(modified, spell, :casting_time, spell.cast_time_ms) == expected_cast
        assert Cooldowns.gcd_duration(modified, SpellLoader.load(116)) == 1500
        assert Enum.any?(events, &match?(%Effects.SpellModifier{operation: 21}, &1))
        {restored, events} = Aura.remove_spells(modified, [bonus_id], 1000)
        assert Cooldowns.gcd_duration(restored, spell) == 1500
        assert Enum.any?(events, &match?(%Effects.SpellModifier{operation: 21, amount: 0}, &1))
      end
    end

    test "Mind Quickening shortens magic cooldowns but leaves rogue attacks at one second", %{caster: caster} do
      {modified, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(23_723), 0)
      assert Cooldowns.gcd_duration(modified, SpellLoader.load(10_917)) == 1127
      assert Cooldowns.gcd_duration(modified, SpellLoader.load(1752)) == 1000
      assert Cooldowns.gcd_duration(modified, SpellLoader.load(23_723)) == 0
    end

    test "Bestial Wrath observes the shared category without triggering another cooldown", %{caster: caster} do
      shot = SpellLoader.load(19_734)
      wrath = SpellLoader.load(19_574)
      assert wrath.gcd_category == 133
      assert wrath.gcd_ms == 0
      caster = Cooldowns.trigger_gcd(caster, shot, 1000)
      assert Cooldowns.on_gcd?(caster, wrath, 2499)
      refute Cooldowns.on_gcd?(caster, wrath, 2500)
      assert Cooldowns.trigger_gcd(caster, wrath, 2600) == caster
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
        player: %Player{},
        internal: %Internal{}
      }
    }
  end
end
