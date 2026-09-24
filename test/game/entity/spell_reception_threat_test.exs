defmodule ThistleTea.Game.Entity.SpellReceptionThreatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "receive/4" do
    test "refreshes threat at impact without replacing the damage snapshot", ctx do
      spell = %Spell{id: 10, school: :physical, effects: [%Effect{type: :school_damage, base_points: 100}]}
      context = %CastContext{caster_guid: ctx.caster, caster_level: 60, threat_multiplier: 0.1}
      Metadata.put(ctx.caster, %{spell_threat: projection(-30)})
      {target, _events} = SpellReception.receive(ctx.target, context, spell, 0)
      assert target.unit.health == 900
      assert_in_delta target.internal.threat[ctx.caster], 70.0, 0.0001

      Metadata.update(ctx.caster, %{spell_threat: %SpellThreat{}})
      {target, _events} = SpellReception.receive(target, context, spell, 1)
      assert_in_delta target.internal.threat[ctx.caster], 170.0, 0.0001
    end
  end

  describe "aura_contexts/2" do
    test "running auras observe modifier gain and removal on subsequent ticks", ctx do
      spell = periodic_spell()
      {target, _events} = AuraLogic.apply_spell(ctx.target, ctx.caster, 60, spell, 0)
      tree = BT.action(fn entity, blackboard -> {:failure, entity, blackboard} end)
      Metadata.put(ctx.caster, %{spell_threat: projection(-30)})
      context = Context.new(1_000, aura_contexts: SpellReception.aura_contexts(target, 1_000))
      {:failure, target} = BehaviorRunner.tick(tree, target, context)
      assert_in_delta target.internal.threat[ctx.caster], 70.0, 0.0001

      Metadata.update(ctx.caster, %{spell_threat: %SpellThreat{}})
      context = Context.new(2_000, aura_contexts: SpellReception.aura_contexts(target, 2_000))
      {:failure, target} = BehaviorRunner.tick(tree, target, context)
      assert_in_delta target.internal.threat[ctx.caster], 170.0, 0.0001
      assert hd(target.unit.auras).cast_context == nil

      {target, _events} = AuraLogic.remove_spells(target, [spell.id], 2_001)
      assert SpellReception.aura_contexts(target, 3_000) == %{}
    end

    test "retains periodic power-burn combat snapshots", ctx do
      context = %CastContext{
        caster_guid: ctx.caster,
        spell_damage_bonus: %{shadow: 75},
        spell_crit_chance: 100,
        critical_threat_multiplier: 0.1
      }

      holder = %Holder{
        spell: periodic_spell(),
        caster_guid: ctx.caster,
        cast_context: context,
        auras: [%Aura{next_tick_at: 1_000}]
      }

      target = %{ctx.target | unit: %{ctx.target.unit | auras: [holder]}}
      Metadata.put(ctx.caster, %{spell_threat: projection(-30)})
      assert SpellReception.aura_contexts(target, 999) == %{}
      [updated] = Map.values(SpellReception.aura_contexts(target, 1_000))
      assert updated.spell_damage_bonus == %{shadow: 75}
      assert updated.spell_crit_chance == 100
      assert updated.critical_threat_multiplier == 1.0
      assert_in_delta updated.threat_multiplier, 0.7, 0.0001
    end

    test "self-cast auras use owner state before metadata publication", ctx do
      guid = ctx.target.object.guid
      {target, _events} = AuraLogic.apply_spell(ctx.target, guid, 60, periodic_spell(), 0)
      modifier = %Holder{spell: %Spell{id: 20}, auras: [%Aura{type: :mod_threat, amount: -30, misc_value: 127}]}
      target = %{target | unit: %{target.unit | auras: [modifier | target.unit.auras]}}
      Metadata.put(guid, %{spell_threat: %SpellThreat{}})
      [context] = Map.values(SpellReception.aura_contexts(target, 1_000))
      assert_in_delta context.threat_multiplier, 0.7, 0.0001
    end

    test "keeps separate combat snapshots for holders from different items", ctx do
      holders =
        for {item, bonus} <- [{101, 50}, {102, 75}] do
          %Holder{
            spell: periodic_spell(),
            caster_guid: ctx.caster,
            item_source: item,
            cast_context: %CastContext{caster_guid: ctx.caster, spell_damage_bonus: %{shadow: bonus}},
            auras: [%Aura{next_tick_at: 1_000}]
          }
        end

      target = %{ctx.target | unit: %{ctx.target.unit | auras: holders}}
      contexts = SpellReception.aura_contexts(target, 1_000)
      assert map_size(contexts) == 2
      assert contexts[{40, ctx.caster, 101}].spell_damage_bonus == %{shadow: 50}
      assert contexts[{40, ctx.caster, 102}].spell_damage_bonus == %{shadow: 75}
    end
  end

  describe "heal/2" do
    test "leech delivery generates threat only for effective healing", ctx do
      target = %{ctx.target | unit: %{ctx.target.unit | health: 1_970}}

      effect =
        Effects.heal_entity(target.object.guid, 100, source_guid: ctx.caster, spell: %Spell{id: 30, school: :shadow})

      Metadata.put(ctx.caster, %{spell_threat: projection(-30)})
      healed = SpellReception.heal(target, effect)
      assert healed.unit.health == 2_000

      assert [%Effects.SpellHeal{damage: 100, proc_type: nil}, %Effects.HealThreat{amount: amount}] =
               healed.internal.events

      assert_in_delta amount, 10.5, 0.0001

      {healed, _events} = Effects.drain(healed)
      assert [%Effects.SpellHeal{damage: 100, proc_type: nil}] = SpellReception.heal(healed, effect).internal.events
      dead = %{target | unit: %{target.unit | health: 0}}
      assert SpellReception.heal(dead, effect) == dead
    end
  end

  defp projection(percent), do: %SpellThreat{school_modifiers: [{127, percent}]}

  defp periodic_spell do
    %Spell{
      id: 40,
      school: :physical,
      duration_ms: 5_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 100, amplitude_ms: 1_000}]
    }
  end

  defp entities(_context) do
    Metadata.init()
    [guid, caster] = guids = Enum.map(1..2, fn _ -> System.unique_integer([:positive]) end)
    on_exit(fn -> Enum.each(guids, &Metadata.delete/1) end)

    %{
      caster: caster,
      target: %Mob{
        object: %Object{guid: guid},
        unit: %Unit{health: 1_000, max_health: 2_000, level: 60, auras: []},
        internal: %Internal{world: WorldRef.open(0), in_combat: true, threat: %{caster => 0.0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
