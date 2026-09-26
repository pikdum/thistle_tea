defmodule ThistleTea.Game.World.Loader.ClassScriptDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ClassScript
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  @moduletag :dbc_db

  setup [:caster]

  describe "load/1" do
    test "talent ranks inherit first-rank proc rules through the talent chain" do
      TalentLoader.init()
      TalentLoader.load_all()

      for {id, first} <- [{12_487, 11_185}, {12_488, 11_185}, {18_095, 18_094}, {19_573, 19_572}] do
        assert SpellLoader.load(id).first_in_chain == first
      end
    end

    test "Nightfall's ranks accept Corruption and Drain Life and trigger one instant Shadow Bolt", %{caster: caster} do
      for {id, chance} <- [{18_094, 2}, {18_095, 4}] do
        talent = %{
          SpellLoader.load(id)
          | proc_rule: %ProcRule{spell_family: 5, family_mask_0: 0xA, proc_flags: 0x40000}
        }

        assert talent.proc_chance == chance
        {buffed, _} = Aura.apply_spell(caster, 1, 60, talent, 0)
        holder = hd(buffed.unit.auras)

        for damage_id <- [172, 689] do
          damage = SpellLoader.load(damage_id)
          assert Proc.eligible?(talent, damage, :deal_harmful_periodic, :normal)
          assert [%Effects.TriggerSpell{spell_id: 17_941}] = ClassScript.events(holder, 1, context(damage))
        end

        refute Proc.eligible?(talent, SpellLoader.load(686), :deal_harmful_spell, :normal)
        trance = SpellLoader.load(17_941)
        assert SpellTarget.redirect_trigger_target(caster, 2, trance) == 1
        {buffed, _} = Aura.apply_spell(buffed, 1, 60, trance, 1_000)
        bolt = SpellLoader.load(686)
        assert Modifiers.integer_value(buffed, bolt, :casting_time, bolt.cast_time_ms) == 0
        assert Enum.find(buffed.unit.auras, &(&1.spell.id == 17_941)).charges == 1
        assert Modifiers.consumable_holder_ids(buffed, bolt) == [17_941]
        {spent, _} = Aura.spend_spell_charges(buffed, [17_941], 2_000)
        assert Modifiers.integer_value(spent, bolt, :casting_time, bolt.cast_time_ms) == bolt.cast_time_ms
        refute Enum.any?(spent.unit.auras, &(&1.spell.id == 17_941))
        {expired, _} = Aura.tick(buffed, 11_000)
        assert Modifiers.integer_value(expired, bolt, :casting_time, bolt.cast_time_ms) == bolt.cast_time_ms
      end
    end

    test "Blizzard ranks select the corresponding slow and only accept Blizzard", %{caster: caster} do
      blizzard = SpellLoader.load(10)

      for {id, slow, speed} <- [{11_185, 12_484, -30}, {12_487, 12_485, -50}, {12_488, 12_486, -65}] do
        talent = %{
          SpellLoader.load(id)
          | proc_rule: %ProcRule{spell_family: 3, family_mask_0: 0x80, proc_flags: 0x50000}
        }

        {buffed, _} = Aura.apply_spell(caster, 1, 60, talent, 0)
        assert Proc.eligible?(talent, blizzard, :deal_harmful_periodic, :normal)
        refute Proc.eligible?(talent, SpellLoader.load(116), :deal_harmful_spell, :normal)

        assert [%Effects.TriggerSpell{spell_id: ^slow}] =
                 ClassScript.events(hd(buffed.unit.auras), 1, context(blizzard))

        chill = SpellLoader.load(slow)
        {slowed, _} = Aura.apply_spell(caster, 1, 60, chill, 0)
        assert [%{auras: [%{type: :mod_decrease_speed, amount: ^speed}]}] = slowed.unit.auras
        assert {expired, _} = Aura.tick(slowed, chill.duration_ms)
        assert expired.unit.auras == []
      end
    end

    test "Mend Pet rank amounts and dispel types come from DBC", %{caster: caster} do
      for {id, chance} <- [{19_572, 15}, {19_573, 50}] do
        talent = %{
          SpellLoader.load(id)
          | proc_rule: %ProcRule{spell_family: 9, family_mask_0: 0x800000, proc_flags: 0x40000, proc_ex: 0x40000}
        }

        {buffed, _} = Aura.apply_spell(caster, 1, 60, talent, 0)
        assert [%{auras: [%{amount: ^chance}]}] = buffed.unit.auras
        mend = SpellLoader.load(136)
        assert Proc.eligible?(talent, mend, :deal_helpful_periodic, :normal)
        refute Proc.eligible?(talent, mend, :deal_helpful_spell, :normal)

        assert [%Effects.TriggerSpell{spell_id: 24_406}] =
                 ClassScript.events(hd(buffed.unit.auras), 1, context(mend), fn -> 0.01 end)
      end

      assert Enum.map(SpellLoader.load(24_406).effects, &{&1.type, &1.misc_value}) ==
               [{:dispel, 7}]
    end

    test "Rejuvenation set bonuses restore the selected resource and Regrowth adds health", %{caster: caster} do
      for {power, spell_id, field, amount} <- [
            {0, 28_722, :power1, 60},
            {1, 28_723, :power2, 20},
            {3, 28_724, :power4, 8}
          ] do
        recipient = %{
          caster
          | unit: %{
              caster.unit
              | power_type: power,
                power1: 0,
                power2: 0,
                power4: 0,
                max_power1: 1_000,
                max_power2: 1_000,
                max_power4: 100
            }
        }

        spell = SpellLoader.load(spell_id)
        {restored, _} = SpellEffect.receive(recipient, %CastContext{caster_guid: 1, caster_level: 60}, spell, 1_000)
        assert Map.fetch!(restored.unit, field) == amount
      end

      bonus = SpellLoader.load(28_750)
      {buffed, _} = Aura.apply_spell(caster, 1, 60, bonus, 0)
      assert [%{auras: [%{type: :mod_increase_health, amount: 50}]}] = buffed.unit.auras
      assert bonus.stack_amount == 7
      assert bonus.duration_ms == 4_000
    end

    test "Netherwind Focus has one cast charge despite its zero DBC proc charges", %{caster: caster} do
      focus = SpellLoader.load(22_008)
      assert focus.proc_charges == 0
      {buffed, _} = Aura.apply_spell(caster, 1, 60, focus, 0)
      assert [%{charges: 1}] = buffed.unit.auras
      fireball = SpellLoader.load(133)
      assert Modifiers.integer_value(buffed, fireball, :casting_time, fireball.cast_time_ms) == 0
      assert Modifiers.consumable_holder_ids(buffed, fireball) == [22_008]
      assert Modifiers.consumable_holder_ids(buffed, SpellLoader.load(2136)) == []
      {spent, _} = Aura.spend_spell_charges(buffed, [22_008], 1_000)
      assert spent.unit.auras == []
    end
  end

  defp caster(_context) do
    %{
      caster: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
        internal: %Internal{}
      }
    }
  end

  defp context(spell), do: %{spell: spell, victim_guid: 2, victim_alive?: true, victim_power_type: 0}
end
