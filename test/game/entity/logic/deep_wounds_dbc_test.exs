defmodule ThistleTea.Game.Entity.Logic.DeepWoundsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:catalog, :entities]

  describe "receive/4" do
    test "critical weapon hits complete every talent rank's bleed chain", %{caster: caster, target: target} do
      for {talent_id, trigger_id, amount} <- [{12_834, 12_162, 6}, {12_849, 12_850, 12}, {12_867, 12_868, 18}] do
        caster = with_talent(caster, talent_id)
        assert hd(caster.unit.auras).spell.proc_rule.proc_ex == 2
        assert trigger(caster, target, :normal) == nil
        assert trigger(caster, target, :miss) == nil
        trigger = trigger(caster, target, :crit)
        assert trigger.spell_id == trigger_id
        dummy = deliver(caster, trigger)
        assert dummy.cast_context.deep_wounds_tick == amount
        {target, events} = SpellEffect.receive(target, dummy.cast_context, dummy.spell, 0)
        bleed = Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
        assert bleed.spell_id == 12_721
        assert bleed.amount == amount
        assert [%Effects.TriggerSpellRequest{source_guid: source}] = Spells.resolve(target, bleed)
        assert source == caster.object.guid
        delivery = deliver(caster, bleed)
        assert delivery.spell.duration_ms == 12_000
        {target, _} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 0)
        assert [%Holder{auras: [%{amount: ^amount, amplitude_ms: 3_000}]}] = target.unit.auras

        target =
          Enum.reduce(1..4, target, fn tick, current ->
            {current, events} = Aura.tick(current, tick * 3_000)
            assert current.unit.health == 1_000 - amount * tick

            assert Enum.any?(
                     events,
                     &match?(%Effects.SpellDamage{spell_id: 12_721, damage: ^amount, periodic?: true}, &1)
                   )

            current
          end)

        assert target.unit.auras == []
      end
    end

    test "melee abilities use critical outcome eligibility", %{caster: caster, target: target} do
      caster = with_talent(caster, 12_867)
      spell = SpellLoader.load(11_567)
      assert trigger(caster, target, :normal, spell) == nil
      assert %Effects.TriggerSpell{spell_id: 12_868} = trigger(caster, target, :crit, spell)
    end

    test "refresh replaces the old bleed and death clears its remaining ticks", %{caster: caster, target: target} do
      caster = with_talent(caster, 12_867)
      delivery = bleed_delivery(caster, target)
      {target, _} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 0)
      {target, _} = Aura.tick(target, 3_000)
      assert target.unit.health == 982
      {target, _} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 4_000)
      assert [%Holder{stacks: 1, expires_at: 16_000, auras: [%{amount: 18}]}] = target.unit.auras
      dead = Core.take_damage(target, 2_000, 4_001)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
      {dead, events} = Aura.tick(dead, 16_000)
      assert dead.unit.health == 0
      refute Enum.any?(events, &is_struct(&1, Effects.SpellDamage))
    end

    test "bleed immunity rejects the proc's aura", %{caster: caster, target: target} do
      caster = with_talent(caster, 12_867)
      delivery = bleed_delivery(caster, target)

      immunity = %Spell{
        id: 999_950,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mechanic_immunity, misc_value: 15}]
      }

      {target, _} = Aura.apply_spell(target, target.object.guid, 60, immunity, 0)
      {target, _} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1)
      refute Enum.any?(target.unit.auras, &(&1.spell.id == 12_721))
      assert target.unit.health == 1_000
    end
  end

  defp with_talent(caster, id) do
    talent = SpellLoader.load(id)
    {caster, _} = Aura.apply_spell(caster, caster.object.guid, 60, talent, 0)
    caster
  end

  defp trigger(caster, target, outcome, spell \\ nil) do
    payload = %{victim_guid: target.object.guid, outcome: outcome, damage: 100}
    caster = AttackFeedback.receive(caster, payload, spell, 0)
    {_, events} = Effects.drain(caster)
    Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
  end

  defp deliver(caster, trigger),
    do: caster |> Spells.resolve(trigger) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))

  defp bleed_delivery(caster, target) do
    delivery = deliver(caster, trigger(caster, target, :crit))
    {_, events} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 0)
    deliver(caster, Enum.find(events, &is_struct(&1, Effects.TriggerSpell)))
  end

  defp catalog(_context) do
    ids = [12_834, 12_849, 12_867, 12_162, 12_850, 12_868, 12_721, 11_567]

    entries = [{SpellProcEvent, 12_834, %ProcRule{proc_ex: 2}} | Enum.map(ids, &{SpellChain, {:chain, &1}, nil})]

    for {table, key, value} <- entries do
      previous = :ets.lookup(table, key)
      :ets.insert(table, {key, value})

      on_exit(fn ->
        :ets.delete(table, key)
        :ets.insert(table, previous)
      end)
    end

    TalentLoader.load_all()
  end

  defp entities(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    target_guid = Guid.runtime(:mob, 1)
    weapon = %{class: 2, subclass: 7, inventory_type: 13}

    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        class: 1,
        level: 60,
        health: 1_000,
        max_health: 1_000,
        min_damage: 100.0,
        max_damage: 140.0,
        mainhand_weapon: weapon,
        base_attack_time: 2_000,
        faction_template: 1,
        auras: []
      },
      player: %Player{},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{
      object: %Object{guid: target_guid},
      unit: %Unit{
        level: 60,
        health: 1_000,
        max_health: 1_000,
        normal_resistance: 100_000,
        faction_template: 14,
        auras: []
      },
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}}
    }

    Metadata.put(target_guid, %{alive?: true, level: 60, unit_flags: 0, faction_template: %FactionTemplate{id: 14}})
    on_exit(fn -> Metadata.delete(target_guid) end)
    %{caster: caster, target: target}
  end
end
