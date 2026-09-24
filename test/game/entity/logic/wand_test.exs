defmodule ThistleTea.Game.Entity.Logic.WandTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "from_caster/3" do
    test "uses the wand's school and damage without attack or spell power", %{caster: caster, spell: spell} do
      context = CastContext.from_caster(caster, spell, 2)
      assert context.spell.school == 2
      assert context.weapon_base_min == 100
      assert context.weapon_base_max == 100
      assert context.attack_power == 0
      assert context.attack_time_ms == 1_500
      assert context.melee_crit_chance == 3.2
      assert context.spell_crit_chance == 3.2
      assert context.attack_skill == 300
      assert spell.school == :physical
    end

    test "weapon talents affect the matching wand and displayed damage, not ordinary spells", context do
      %{caster: caster, spell: spell} = context

      holder = %Holder{
        spell: %Spell{id: 14_509, equipped_item_class: 2, equipped_item_subclass_mask: 524_288},
        auras: [%Aura{type: :mod_damage_percent_done, amount: 25, misc_value: 126}]
      }

      caster = %{caster | unit: %{caster.unit | auras: [holder]}}
      assert CastContext.from_caster(caster, spell, 2).damage_done_multiplier == 1.25

      fireball = %{spell | attributes: MapSet.new(), school: :fire, effects: [%Effect{type: :school_damage}]}
      assert CastContext.from_caster(caster, fireball, 2).damage_done_multiplier == 1.0

      unit = Stats.recompute(caster.unit)
      assert unit.min_ranged_damage == 125
      assert unit.max_ranged_damage == 125
      assert Stats.recompute(unit).min_ranged_damage == 125
      assert Stats.recompute(%{unit | auras: []}).min_ranged_damage == 100
    end
  end

  describe "receive/4" do
    test "bypasses armor and melee avoidance, uses ranged procs and 150 percent criticals", context do
      %{caster: caster, target: target, spell: spell} = context
      cast = guaranteed_hit(caster, spell)
      {damaged, events} = SpellEffect.receive(target, cast, cast.spell, 0)
      assert damaged.unit.health == 900
      assert [%Effects.SpellDamage{damage: 100, resisted: 0, proc_type: :deal_ranged_attack}] = damage_events(events)

      critical = %{cast | melee_crit_chance: 100}
      {damaged, events} = SpellEffect.receive(target, critical, critical.spell, 0)
      assert damaged.unit.health == 850
      assert [%Effects.SpellDamage{damage: 150, crit?: true}] = damage_events(events)
    end

    test "applies school immunity and partial resistance with matching combat feedback", context do
      %{caster: caster, target: target, spell: spell} = context
      cast = guaranteed_hit(caster, spell)
      immune = %{target | unit: %{target.unit | auras: [holder(:school_immunity, 0, 4)]}}
      {unchanged, events} = SpellEffect.receive(immune, cast, cast.spell, 0)
      assert unchanged.unit.health == 1_000
      assert Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :immune}, &1))

      resistant = %{target | unit: %{target.unit | fire_resistance: 300}}
      :rand.seed(:exsss, {1, 2, 3})

      resisted =
        for _ <- 1..30 do
          {damaged, events} = SpellEffect.receive(resistant, cast, cast.spell, 0)
          assert [%Effects.SpellDamage{damage: damage, resisted: resisted}] = damage_events(events)
          assert damaged.unit.health == 1_000 - damage
          assert damage + resisted == 100
          resisted
        end

      assert Enum.any?(resisted, &(&1 > 0))
    end

    test "uses ranged hit modifiers and excludes Hunter's Mark attack power", context do
      %{caster: caster, target: target, spell: spell} = context
      cast = guaranteed_hit(caster, spell)
      marked = %{target | unit: %{target.unit | auras: [holder(:ranged_attack_power_attacker_bonus, 1_400, 0)]}}
      {damaged, _events} = SpellEffect.receive(marked, cast, cast.spell, 0)
      assert damaged.unit.health == 900

      missed = %{cast | hit_chance_bonus: -100, attack_skill: 1}
      :rand.seed(:exsss, {1, 2, 3})
      outcomes = for _ <- 1..30, do: SpellEffect.receive(target, missed, missed.spell, 0)
      assert Enum.any?(outcomes, fn {result, _events} -> result.unit.health == 1_000 end)
    end
  end

  describe "start/5" do
    test "arms once, waits 500 milliseconds, repeats at weapon speed, and cancels before launch", context do
      %{caster: caster, spell: spell, perception: perception} = context
      armed = Casting.start(caster, spell, Target.unit(2), 1_000)
      assert armed.internal.casting == nil
      assert armed.internal.auto_shot.next_at == 1_500
      assert [%Effects.SpellCastResult{}] = armed.internal.events
      armed = %{armed | internal: %{armed.internal | events: []}}

      {{:running, 50}, waiting} = BT.tick(Ranged.sequence(), armed, Context.new(1_499, perception: perception))
      assert waiting.internal.events == []
      {{:running, 1_500}, queued} = BT.tick(Ranged.sequence(), armed, Context.new(1_500, perception: perception))
      assert [%Effects.LaunchRanged{kind: :repeat}] = queued.internal.events
      assert queued.internal.auto_shot.next_at == 3_000
      {_status, duplicate} = BT.tick(Ranged.sequence(), queued, Context.new(1_600, perception: perception))
      assert length(duplicate.internal.events) == 1

      {cancelled, effects} = AutoRepeat.cancel(armed)
      assert cancelled.internal.auto_shot == nil
      assert [%Effects.CancelAutoRepeat{}] = effects
    end

    test "movement and another spell cancel wand shooting while bow attacks pause", context do
      %{caster: caster, spell: spell, perception: perception} = context
      armed = Casting.start(caster, spell, Target.unit(2), 0)
      moved = %{armed | movement_block: %{armed.movement_block | movement_flags: 1}}
      {_status, stopped} = BT.tick(Ranged.sequence(), moved, Context.new(1_000, perception: perception))
      assert stopped.internal.auto_shot == nil
      assert Enum.any?(stopped.internal.events, &is_struct(&1, Effects.CancelAutoRepeat))

      other = Casting.start(armed, %Spell{id: 133, cast_time_ms: 2_000}, Target.unit(2), 200)
      assert other.internal.auto_shot == nil
      assert other.internal.casting.spell.id == 133

      bow = Casting.start(caster, %{spell | id: 75, dmg_class: 3}, Target.unit(2), 0)
      paused = AutoRepeat.interrupt(bow, 1_000)
      assert paused.internal.auto_shot.next_at == 1_500
      resumed = AutoRepeat.resume(paused, 3_000)
      assert resumed.internal.auto_shot.next_at == 3_500
      assert AutoRepeat.resume(resumed, 3_100).internal.auto_shot.next_at == 3_500
      refute Enum.any?(paused.internal.events, &is_struct(&1, Effects.CancelAutoRepeat))
    end

    test "toggling Shoot preserves the last launch's weapon cooldown", %{caster: caster, spell: spell} do
      armed = Casting.start(caster, spell, Target.unit(2), 0)
      fired = AutoRepeat.launched(armed, armed.internal.auto_shot, 500)
      {stopped, _effects} = AutoRepeat.cancel(fired)
      restarted = Casting.start(stopped, spell, Target.unit(2), 600)
      assert restarted.internal.auto_shot.next_at == 2_000
    end

    test "lost sight, dead targets, range and caster death clear the repeat", context do
      %{caster: caster, spell: spell, perception: perception} = context
      armed = Casting.start(caster, spell, Target.unit(2), 0)
      observation = perception.entities[2]

      for changed <- [
            %{observation | metadata: %{alive?: false}},
            %{observation | line_of_sight?: false},
            %{observation | distance: 40.0}
          ] do
        context = Context.new(500, perception: %{perception | entities: %{2 => changed}})
        {_status, stopped} = BT.tick(Ranged.sequence(), armed, context)
        assert stopped.internal.auto_shot == nil
        refute Enum.any?(stopped.internal.events, &is_struct(&1, Effects.LaunchRanged))
      end

      assert Core.take_damage(armed, 1_000, 200).internal.auto_shot == nil
    end
  end

  defp guaranteed_hit(caster, spell) do
    %{CastContext.from_caster(caster, spell, 2) | hit_chance_bonus: 100, melee_crit_chance: 0}
  end

  defp damage_events(events), do: Enum.filter(events, &is_struct(&1, Effects.SpellDamage))

  defp holder(type, amount, mask),
    do: %Holder{spell: %Spell{id: 90_002}, auras: [%Aura{type: type, amount: amount, misc_value: mask}]}

  defp entities(_context) do
    wand = %ItemTemplate{class: 2, subclass: 19, inventory_type: 26, dmg_type1: 2, delay: 1_500}

    unit = %Unit{
      health: 1_000,
      max_health: 1_000,
      level: 60,
      class: 8,
      auras: [],
      normal_resistance: 10_000,
      ranged_weapon: wand,
      ranged_attack_time: 1_500,
      base_ranged_attack_time: 1_500,
      base_ranged_min_damage: 100,
      base_ranged_max_damage: 100,
      base_min_damage: 1_000,
      base_max_damage: 1_000,
      attack_power: 14_000,
      ranged_attack_power: 14_000,
      equipment_bonuses: %{spell_fire: 10_000}
    }

    caster = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{ranged_crit_percentage: 0},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{
      object: %Object{guid: 2},
      unit: %{unit | auras: [holder(:mod_parry_percent, 100, 0)]},
      internal: %Internal{}
    }

    spell = %Spell{
      id: 5019,
      dmg_class: 1,
      school: :physical,
      range_yards: 30.0,
      attributes: MapSet.new([:uses_ranged_slot, :auto_repeat, :ability]),
      effects: [%Effect{type: :weapon_damage_noschool, index: 0, base_points: 0, implicit_target_a: :target_enemy}]
    }

    observation = %Observation{
      guid: 2,
      position: {WorldRef.open(0), 20.0, 0.0, 0.0},
      distance: 20.0,
      metadata: %{alive?: true}
    }

    perception = Perception.new(0, nil, %{2 => observation}, %{players: [], mobs: []})
    %{caster: caster, target: target, spell: spell, perception: perception}
  end
end
