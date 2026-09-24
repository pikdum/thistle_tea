defmodule ThistleTea.Game.World.Loader.HealingBonusDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.HealingReceived
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db
  @flash_ranks [19_750, 19_939, 19_940, 19_941, 19_942, 19_943]

  setup [:coefficients]

  describe "load/1" do
    test "Amplify and Dampen Magic replace one another across ranks and casters" do
      for id <- [604, 1008, 8450, 8451, 8455, 10_169, 10_170, 10_173, 10_174] do
        assert SpellLoader.load(id).exclusive_category == :mage_magic
      end

      for ids <- [[10_170, 10_174, 1008], [10_174, 10_170, 604]] do
        Enum.reduce(Enum.with_index(ids, 1), recipient(), fn {id, caster}, target ->
          {target, _events} = Aura.apply_spell(target, caster, 60, SpellLoader.load(id), 1_000 * caster)
          assert [holder] = target.unit.auras
          assert holder.spell.id == id
          assert holder.caster_guid == caster
          target
        end)
      end
    end

    test "Amplify and Dampen Magic scale differently for Flash Heal and Renew" do
      direct = SpellLoader.load(10_917)
      hot = SpellLoader.load(10_929)

      for {id, direct_amount, periodic_amount} <- [{10_170, 264, 230}, {10_174, 122, 164}] do
        {recipient, _events} = Aura.apply_spell(recipient(), 1, 60, SpellLoader.load(id), 0)
        assert HealingReceived.spell_amount(recipient, 200, direct, hd(direct.effects)) == direct_amount
        assert HealingReceived.spell_amount(recipient, 200, hot, hd(hot.effects), damage_type: :dot) == periodic_amount
      end
    end

    test "all Flash of Light ranks inherit the triggered heal coefficient in single and bulk loads" do
      bulk = SpellLoader.build_spellbook(@flash_ranks)

      for id <- @flash_ranks, spell <- [SpellLoader.load(id), bulk[id]] do
        effect = hd(spell.effects)
        assert effect.type == :heal
        assert effect.bonus_coefficient == 0.429
        assert Coefficient.bonus(1_000, spell, effect, :direct) == 429
      end
    end

    test "Blessing of Light applies the appropriate coefficient to both Paladin heals" do
      for id <- [19_979, 25_890] do
        {recipient, _events} = Aura.apply_spell(recipient(), 1, 60, SpellLoader.load(id), 0)
        holy = SpellLoader.load(25_292)
        flash = SpellLoader.load(19_943)
        assert HealingReceived.spell_amount(recipient, 500, holy, hd(holy.effects)) == 785
        assert HealingReceived.spell_amount(recipient, 500, flash, hd(flash.effects)) == 549
      end
    end

    test "Healing Way stacks benefit Healing Wave without affecting other Shaman heals" do
      spell = SpellLoader.load(29_203)
      assert spell.stack_amount == 3
      recipient = Enum.reduce(1..3, recipient(), fn _, target -> elem(Aura.apply_spell(target, 1, 60, spell, 0), 0) end)

      for {id, expected} <- [{331, 236}, {8004, 200}, {1064, 200}] do
        healing = SpellLoader.load(id)
        assert HealingReceived.spell_amount(recipient, 200, healing, hd(healing.effects)) == expected
      end

      {recipient, _events} = Aura.expire_due(recipient, spell.duration_ms)
      healing = SpellLoader.load(331)
      assert HealingReceived.spell_amount(recipient, 200, healing, hd(healing.effects)) == 200
    end
  end

  defp recipient do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 1_000, auras: []},
      internal: %Internal{}
    }
  end

  defp coefficients(_context) do
    values = [{10_917, 0.429}, {10_929, 0.2}, {19_993, 0.429}, {25_292, 0.714}] ++ Enum.map(@flash_ranks, &{&1, 0.0})

    for {id, coefficient} <- values do
      key = {:coefficients, id}
      previous = :ets.lookup(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, {key, {coefficient, -1.0, -1.0}})

      on_exit(fn ->
        :ets.delete(SpellEffectOverride, key)
        :ets.insert(SpellEffectOverride, previous)
      end)
    end

    :ok
  end
end
