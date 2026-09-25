defmodule ThistleTea.Game.Entity.Logic.RacialDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.HealingReceived
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  setup [:caster]

  describe "receive/4" do
    test "every Berserking variant captures health for melee, ranged and spell haste", %{caster: caster} do
      for id <- [20_554, 26_296, 26_297], {health, amount} <- [{1000, 10}, {700, 20}, {400, 30}] do
        caster = %{caster | unit: %{caster.unit | health: health}}
        result = cast(caster, id, 1000)
        assert [%{spell: %{id: 26_635}, auras: auras, expires_at: 11_000}] = result.unit.auras

        assert Enum.map(auras, &{&1.type, &1.amount}) == [
                 mod_melee_haste: amount,
                 mod_ranged_haste: amount,
                 mod_casting_speed: amount
               ]

        assert result.unit.base_attack_time == trunc(2000 * 100 / (100 + amount))
        assert result.unit.offhand_attack_time == trunc(1600 * 100 / (100 + amount))
        assert result.unit.ranged_attack_time == trunc(2800 * 100 / (100 + amount))
        assert_in_delta result.unit.mod_cast_speed, 100 / (100 + amount), 0.00001
        healed = Core.heal(result, 1000)
        assert healed.unit.base_attack_time == result.unit.base_attack_time
        {expired, _} = Aura.tick(healed, 11_000)
        assert expired.unit.base_attack_time == 2000
        assert expired.unit.ranged_attack_time == 2800
        assert expired.unit.mod_cast_speed == 1.0
      end
    end

    test "Berserking retains each class's resource cost", %{caster: caster} do
      assert Resources.power_cost(caster, SpellLoader.load(20_554)) == 70
      assert Resources.power_cost(caster, SpellLoader.load(26_296)) == 50
      assert Resources.power_cost(caster, SpellLoader.load(26_297)) == 10
    end

    test "Blood Fury grants base melee attack power and a longer healing penalty", %{caster: caster} do
      buffed = cast(caster, 20_572, 1000)
      assert buffed.unit.attack_power == caster.unit.attack_power + 90
      assert buffed.unit.ranged_attack_power == caster.unit.ranged_attack_power
      stronger = Stats.recompute(%{buffed.unit | base_strength: buffed.unit.base_strength + 20})
      assert stronger.attack_power == buffed.unit.attack_power + 40
      assert Aura.flat_amount(%{unit: stronger}, :mod_attack_power) == 90
      assert HealingReceived.amount(buffed, 200) == 100
      {after_buff, _} = Aura.tick(buffed, 16_000)
      assert after_buff.unit.attack_power == caster.unit.attack_power
      assert HealingReceived.amount(after_buff, 200) == 100
      {expired, _} = Aura.tick(after_buff, 26_000)
      assert HealingReceived.amount(expired, 200) == 200
      assert expired.unit.auras == []
    end

    test "canceling Blood Fury retains its penalty and death removes both", %{caster: caster} do
      buffed = cast(caster, 20_572, 1000)
      {cancelled, _} = Aura.cancel_spell(buffed, 23_234, 2000)
      assert cancelled.unit.attack_power == caster.unit.attack_power
      assert HealingReceived.amount(cancelled, 200) == 100
      dead = Core.take_damage(buffed, 10_000, 2000)
      assert dead.unit.health == 0
      assert dead.unit.attack_power == caster.unit.attack_power
      assert dead.unit.auras == []
    end

    test "Berserking death cleanup restores all speed fields", %{caster: caster} do
      dead = caster |> cast(20_554, 1000) |> Core.take_damage(10_000, 2000)
      assert dead.unit.health == 0
      assert dead.unit.base_attack_time == 2000
      assert dead.unit.ranged_attack_time == 2800
      assert dead.unit.mod_cast_speed == 1.0
      assert dead.unit.auras == []
    end
  end

  defp cast(caster, id, now) do
    spell = SpellLoader.load(id)
    context = CastContext.from_caster(caster, spell, caster.object.guid)
    {caster, events} = SpellEffect.receive(caster, context, spell, now)

    Enum.reduce(events, caster, fn
      %Effects.TriggerSpell{} = trigger, current ->
        Enum.reduce(Spells.resolve(current, trigger), current, fn
          %Effects.DeliverSpell{cast_context: context, spell: spell}, target ->
            {target, _events} = SpellEffect.receive(target, context, spell, now)
            target

          _event, target ->
            target
        end)

      _event, current ->
        current
    end)
  end

  defp caster(_context) do
    unit =
      Stats.recompute(%Unit{
        race: 8,
        class: 1,
        level: 60,
        health: 1000,
        max_health: 1000,
        base_mana: 1000,
        power1: 1000,
        power2: 1000,
        max_power2: 1000,
        power4: 100,
        max_power4: 100,
        base_strength: 100,
        base_agility: 50,
        base_intellect: 0,
        base_melee_attack_time: 2000,
        base_offhand_attack_time: 1600,
        base_ranged_attack_time: 2800,
        equipment_bonuses: %{attack_power: 120},
        auras: []
      })

    %{
      caster: %Character{
        object: %Object{guid: System.unique_integer([:positive]) + 90_000_000},
        unit: unit,
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
