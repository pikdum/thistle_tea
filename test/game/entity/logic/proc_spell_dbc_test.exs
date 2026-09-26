defmodule ThistleTea.Game.Entity.Logic.ProcSpellDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellEffectOverride
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Loader.Talent
  alias ThistleTea.Game.World.Metadata

  @moduletag :dbc_db

  setup [:catalog, :character]

  describe "receive/4" do
    test "all Blessed Recovery ranks heal three times and expire", %{character: character} do
      for {talent, trigger, amount} <- [{27_811, 27_813, 8}, {27_815, 27_817, 16}, {27_816, 27_818, 25}] do
        character = with_aura(character, talent)
        passive = hd(character.unit.auras)
        assert passive.spell.proc_rule.proc_ex == 2
        assert Enum.map(passive.auras, & &1.amount) == [amount]
        {character, [event]} = reaction(character, 300, 0)
        assert event.spell_id == trigger
        character = apply_trigger(character, character, event, 0)
        hot = Enum.find(character.unit.auras, &(&1.spell.id == trigger))
        assert hot.expires_at == 6_000
        assert [%{amount: ^amount, amplitude_ms: 2_000}] = hot.auras

        character =
          Enum.reduce(1..3, character, fn tick, character ->
            {character, events} = Aura.tick(character, tick * 2_000)
            assert character.unit.health == 1_000 + tick * amount
            assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: ^amount}, &1))
            character
          end)

        refute Enum.any?(character.unit.auras, &(&1.spell.id == trigger))
      end
    end

    test "a new critical hit replaces recovery strength without accumulating it", %{character: character} do
      character = with_aura(character, 27_816)
      {character, [event]} = reaction(character, 300, 0)
      character = apply_trigger(character, character, event, 0)
      {character, _} = Aura.tick(character, 2_000)
      {character, [event]} = reaction(character, 900, 3_000)
      character = apply_trigger(character, character, event, 3_000)
      hot = Enum.find(character.unit.auras, &(&1.spell.id == 27_818))
      assert hot.stacks == 1
      assert hot.expires_at == 9_000
      assert [%{amount: 75, next_tick_at: 4_000}] = hot.auras
      {character, _} = Aura.tick(character, 4_000)
      assert character.unit.health == 1_100
      dead = Core.take_damage(character, 5_000, 4_500)
      {dead, events} = Aura.tick(dead, 6_000)
      assert dead.unit.health == 0
      refute Enum.any?(events, &is_struct(&1, Effects.PeriodicAuraLog))
      refute Enum.any?(dead.unit.auras, &(&1.spell.id == 27_818))
    end

    test "a fully overhealing cast shields its actual recipient through owner feedback", %{character: character} do
      caster = with_aura(character, 26_467)
      target_guid = System.unique_integer([:positive]) + 50_000_000
      target = %{character | object: %Object{guid: target_guid}, unit: %{character.unit | health: 5_000}}
      Metadata.put(target_guid, %{alive?: true, level: 60})
      on_exit(fn -> Metadata.delete(target_guid) end)
      {:ok, _} = Entity.register(caster.object.guid)
      heal = SpellLoader.load(2061)
      context = CastContext.from_caster(caster, heal, target_guid)
      {target, events} = SpellEffect.receive(target, context, heal, 0)
      assert target.unit.health == 5_000
      healed = Enum.find(events, &is_struct(&1, Effects.SpellHeal))
      assert healed.damage > 0
      EventSink.emit(target, healed)
      assert_receive {:"$gen_cast", {:spell_outcome, feedback}}
      assert feedback.damage == healed.damage
      assert feedback.victim_guid == target_guid
      caster = SpellFeedback.receive(caster, feedback, heal, 0)
      {caster, events} = Effects.drain(caster)
      proc = Enum.find(events, &match?(%Effects.TriggerSpell{spell_id: 26_470}, &1))
      assert proc.amount == div(healed.damage * 15, 100)
      target = apply_trigger(caster, target, proc, 0)
      shield = Enum.find(target.unit.auras, &(&1.spell.id == 26_470))
      assert shield.caster_guid == caster.object.guid
      assert [%{amount: amount, misc_value: 127}] = shield.auras
      assert amount == proc.amount
      assert shield.expires_at == 8_000
      {target, 0} = Aura.absorb_damage(target, amount - 1, :fire, 1_000)
      assert [%{auras: [%{amount: 1}]}] = target.unit.auras
      {target, 0} = Aura.absorb_damage(target, 1, :physical, 2_000)
      assert target.unit.auras == []
    end

    test "shield refresh replaces the remaining amount and expiry clears it", %{character: character} do
      caster = with_aura(character, 26_467)

      context = %{
        victim_guid: 1,
        victim_alive?: true,
        proc_type: :deal_helpful_spell,
        damage: 1_000,
        outcome: :normal,
        spell: SpellLoader.load(2061),
        now: 0
      }

      {caster, [event]} = Aura.reactions(caster, :spell_hit_dealt, context)
      target = apply_trigger(caster, character, event, 0)
      {target, 0} = Aura.absorb_damage(target, 100, :physical, 1_000)
      {caster, [event]} = Aura.reactions(caster, :spell_hit_dealt, %{context | damage: 200, now: 2_000})
      target = apply_trigger(caster, target, event, 2_000)
      assert [%{stacks: 1, expires_at: 10_000, auras: [%{amount: 30}]}] = target.unit.auras
      {target, _} = Aura.expire_due(target, 10_000)
      assert target.unit.auras == []
      dead = %{character | unit: %{character.unit | health: 0}}
      assert Spells.resolve(dead, event) == []
    end
  end

  defp reaction(character, damage, now) do
    Aura.reactions(character, :hit_taken, %{
      attacker_guid: 2,
      damage: damage,
      outcome: :crit,
      proc_type: :take_melee_swing,
      now: now
    })
  end

  defp with_aura(character, id) do
    {character, _} = Aura.apply_spell(character, character.object.guid, 60, SpellLoader.load(id), 0)
    character
  end

  defp apply_trigger(caster, target, event, now) do
    delivery = caster |> Spells.resolve(event) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
    assert delivery.target_guid == target.object.guid
    {target, _} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, now)
    target
  end

  defp catalog(_context) do
    ids = [27_811, 27_815, 27_816, 27_813, 27_817, 27_818, 26_467, 26_470, 2061]

    entries =
      [{SpellProcEvent, 27_811, %ProcRule{proc_ex: 2}}] ++
        Enum.map(ids, &{SpellChain, {:chain, &1}, nil}) ++
        Enum.map([27_813, 27_817, 27_818, 26_470], &{SpellEffectOverride, {:coefficients, &1}, {0.0, -1.0, -1.0}})

    for {table, key, value} <- entries do
      previous = :ets.lookup(table, key)
      :ets.insert(table, {key, value})

      on_exit(fn ->
        :ets.delete(table, key)
        :ets.insert(table, previous)
      end)
    end

    Talent.load_all()
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 5_000, auras: [], equipment_bonuses: %{healing: 1_000}},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{character: character}
  end
end
