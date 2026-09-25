defmodule ThistleTea.Game.Entity.Logic.Aura.HeartbeatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:recipients]

  describe "apply_spell/4" do
    test "samples the player distribution independently of caster ownership", ctx do
      for {sample, delay} <- [{0.01, 9_000}, {0.5, 12_000}, {0.99, 15_000}] do
        context = %{ctx.context | heartbeat_sample: sample, caster_type: :mob}
        {player, _} = Aura.apply_spell(ctx.player, context, ctx.spell, -50_000)
        [holder] = player.unit.auras
        assert_in_delta holder.heartbeat.break_at, -50_000 + delay, 1
        assert holder.heartbeat.next_check_at == nil
        assert Aura.next_event_at(player) == holder.heartbeat.break_at
      end
    end

    test "excludes positive, permanent, short, and unflagged holders", ctx do
      for spell <- [
            %{ctx.spell | duration_ms: 10_000},
            %{ctx.spell | duration_ms: -1},
            %{ctx.spell | duration_ms: nil},
            %{ctx.spell | attributes: MapSet.new()},
            %{ctx.spell | effects: [%Effect{type: :apply_aura, aura: :mod_stat, base_points: 3}]}
          ],
          entity <- [ctx.player, ctx.mob] do
        {applied, _} = Aura.apply_spell(entity, %{ctx.context | target_hostile?: false}, spell, -50_000)
        assert [%Holder{heartbeat: nil}] = applied.unit.auras
      end
    end

    test "engineering controls use player breaks without creature checks", ctx do
      for id <- [13_181, 13_327] do
        spell = %{ctx.spell | id: id, attributes: MapSet.new()}
        {player, _} = Aura.apply_spell(ctx.player, ctx.context, spell, 0)
        assert hd(player.unit.auras).heartbeat.break_at == 12_000
        {mob, _} = Aura.apply_spell(ctx.mob, ctx.context, spell, 0)
        assert hd(mob.unit.auras).heartbeat == nil
      end
    end

    test "player pets and charmed creatures may receive both checks", ctx do
      pet = %{ctx.mob | internal: %{ctx.mob.internal | pet: %Pet{owner_guid: 3}}}
      charmed = %{ctx.mob | unit: %{ctx.mob.unit | charmed_by: 3}}

      for entity <- [pet, charmed] do
        {applied, _} = Aura.apply_spell(entity, ctx.context, ctx.spell, 0)
        heartbeat = hd(applied.unit.auras).heartbeat
        assert heartbeat.break_at == 12_000
        assert heartbeat.next_check_at == 5_000
      end

      npc_pet = %{pet | internal: %{pet.internal | pet: %Pet{owner_guid: ctx.mob.object.guid}}}
      {applied, _} = Aura.apply_spell(npc_pet, ctx.context, ctx.spell, 0)
      assert hd(applied.unit.auras).heartbeat.break_at == nil
    end

    test "fear, roots, pacify-silence, and confusion omit creature checks", ctx do
      for type <- [:mod_fear, :mod_root, :mod_pacify_silence, :mod_confuse] do
        spell = %{ctx.spell | effects: ctx.spell.effects ++ [%Effect{index: 1, type: :apply_aura, aura: type}]}
        {mob, _} = Aura.apply_spell(ctx.mob, ctx.context, spell, 0)
        assert hd(mob.unit.auras).heartbeat == nil
        {player, _} = Aura.apply_spell(ctx.player, ctx.context, spell, 0)
        assert hd(player.unit.auras).heartbeat.break_at == 12_000
      end
    end

    test "snapshots spell hit, binary resistance, penetration, and always-hit", ctx do
      mob = %{ctx.mob | unit: %{ctx.mob.unit | shadow_resistance: 100}}
      spell = %{ctx.spell | dmg_class: 1}
      {applied, _} = Aura.apply_spell(mob, %{ctx.context | spell_hit_bonus: 4}, spell, 0)
      assert hd(applied.unit.auras).heartbeat.hit_chance_bp == 7_500

      context = %{ctx.context | spell_hit_bonus: 4, resistance_penetration: [{32, -100}]}
      {applied, _} = Aura.apply_spell(mob, context, spell, 0)
      assert hd(applied.unit.auras).heartbeat.hit_chance_bp == 9_900

      spell = %{spell | attributes: MapSet.put(spell.attributes, :always_hit)}
      {applied, _} = Aura.apply_spell(mob, ctx.context, spell, 0)
      assert hd(applied.unit.auras).heartbeat.hit_chance_bp == 10_000
      {retained, _} = tick(applied, 5_000, 0)
      assert length(retained.unit.auras) == 1
    end

    test "includes incoming hit modifiers and avoidance in area heartbeat checks", ctx do
      defense = %Spell{
        id: 999_123,
        duration_ms: 60_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_attacker_spell_hit_chance, base_points: -10, misc_value: 32},
          %Effect{index: 1, type: :apply_aura, aura: :mod_aoe_avoidance, base_points: 25}
        ]
      }

      {mob, _} = Aura.apply_spell(ctx.mob, ctx.mob.object.guid, 60, defense, 0)
      spell = %{ctx.spell | effects: Enum.map(ctx.spell.effects, &%{&1 | area_target?: true})}
      {applied, _} = Aura.apply_spell(mob, ctx.context, spell, 0)
      holder = Enum.find(applied.unit.auras, &(&1.spell.id == spell.id))
      assert holder.heartbeat.hit_chance_bp == 6_100
    end

    test "refresh retains its quantile and scales breaks with diminishing returns", ctx do
      spell = %{ctx.spell | mechanic: 7, effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_root}]}
      {player, _} = Aura.apply_spell(ctx.player, ctx.context, spell, 0)
      assert hd(player.unit.auras).heartbeat.break_at == 12_000

      {player, _} = Aura.apply_spell(player, %{ctx.context | heartbeat_sample: 0.99}, spell, 1_000)
      assert hd(player.unit.auras).heartbeat.break_at == 7_000
      assert hd(player.unit.auras).expires_at == 11_000

      {player, _} = Aura.apply_spell(player, ctx.context, spell, 2_000)
      assert hd(player.unit.auras).heartbeat.break_at == 5_000
      assert hd(player.unit.auras).expires_at == 7_000
      {broken, _} = Aura.tick(player, 5_000)
      refute broken.internal.rooted?
      assert broken.internal.diminishing_returns.controlled_root.applications == 3
      assert broken.internal.diminishing_returns.controlled_root.reset_at == 20_000
    end

    test "refresh retains the creature timer and original hit chance", ctx do
      {mob, _} = Aura.apply_spell(ctx.mob, ctx.context, ctx.spell, 0)
      {mob, _} = Aura.apply_spell(mob, %{ctx.context | caster_level: 1}, ctx.spell, 4_000)
      assert hd(mob.unit.auras).heartbeat.next_check_at == 5_000
      assert hd(mob.unit.auras).heartbeat.hit_chance_bp == 9_600
      {mob, _} = Aura.remove_spells(mob, [ctx.spell.id], 4_500)
      {mob, _} = Aura.apply_spell(mob, %{ctx.context | caster_level: 1}, ctx.spell, 5_000)
      assert hd(mob.unit.auras).heartbeat.next_check_at == 10_000
      assert hd(mob.unit.auras).heartbeat.hit_chance_bp == 2_200
    end
  end

  describe "tick/3" do
    test "player breaks clear control at their sampled deadline", ctx do
      {player, _} = Aura.apply_spell(ctx.player, ctx.context, ctx.spell, 0)
      {early, _} = Aura.tick(player, 11_999)
      assert early.internal.rooted?
      {broken, events} = Aura.tick(early, 12_000)
      assert broken.unit.auras == []
      refute broken.internal.rooted?
      assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
    end

    test "checks the inclusive creature roll only on five-second boundaries", ctx do
      {mob, _} = Aura.apply_spell(ctx.mob, ctx.context, ctx.spell, 0)
      assert Aura.next_event_at(mob) == 5_000
      {early, _} = tick(mob, 4_999, 0)
      assert early.unit.auras == mob.unit.auras
      {retained, _} = tick(mob, 5_000, 400)
      assert Aura.next_event_at(retained) == 10_000
      {broken, _} = tick(mob, 5_000, 399)
      assert broken.unit.auras == []
      refute broken.internal.rooted?
      assert Bitwise.band(broken.unit.flags, 0x00040000) == 0
      assert Aura.next_event_at(broken) == nil
    end

    test "a late tick rolls once and advances beyond now", ctx do
      {mob, _} = Aura.apply_spell(ctx.mob, ctx.context, ctx.spell, 0)
      {mob, _} = tick(mob, 12_000, 10_000)
      assert Aura.next_event_at(mob) == 15_000
      {broken, _} = tick(mob, 15_000, 0)
      assert broken.unit.auras == []
    end

    test "breaks before due periodic effects and retires single-target claims", ctx do
      effect = %Effect{index: 1, type: :apply_aura, aura: :periodic_damage, base_points: 10, amplitude_ms: 5_000}
      spell = %{ctx.spell | custom_flags: 256, effects: ctx.spell.effects ++ [effect]}
      {mob, _} = Aura.apply_spell(ctx.mob, ctx.context, spell, 0)
      {broken, events} = tick(mob, 5_000, 0)
      assert broken.unit.health == 100
      assert broken.unit.auras == []
      assert Enum.any?(events, &match?(%Effects.SingleTargetAurasChanged{claims: []}, &1))
      refute Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
    end

    test "dispel and death leave no scheduled break to restore the holder", ctx do
      {player, _} = Aura.apply_spell(ctx.player, ctx.context, %{ctx.spell | dispel_type: 1}, 0)
      {dispelled, _} = Aura.dispel(player, 1, 1_000)
      dead = Core.take_damage(player, 100, 1_000)

      for entity <- [dispelled, dead] do
        {entity, _} = Aura.tick(entity, 15_000)
        assert entity.unit.auras == []
        assert Aura.next_event_at(entity) == nil
      end
    end
  end

  describe "delay_source_spell/5" do
    test "channel pushback advances player elapsed time without shifting creature checks", ctx do
      pet = %{ctx.mob | internal: %{ctx.mob.internal | pet: %Pet{owner_guid: 3}}}
      {pet, _} = Aura.apply_spell(pet, ctx.context, ctx.spell, 0)
      pet = Aura.delay_source_spell(pet, ctx.spell.id, 1, 3_000, 2_000)
      [holder] = pet.unit.auras
      assert holder.expires_at == 17_000
      assert holder.heartbeat.break_at == 9_000
      assert holder.heartbeat.next_check_at == 5_000
      {pet, _} = tick(pet, 5_000, 10_000)
      {broken, _} = Aura.tick(pet, 9_000)
      assert broken.unit.auras == []
    end
  end

  defp tick(entity, now, roll) do
    [holder] = entity.unit.auras
    contexts = %{{holder.spell.id, holder.caster_guid, holder.item_source} => %CastContext{heartbeat_roll: roll}}
    Aura.tick(entity, now, contexts)
  end

  defp recipients(_context) do
    unit = %Unit{health: 100, max_health: 100, level: 60, auras: []}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}

    %{
      player: %Character{
        object: %Object{guid: 2},
        unit: unit,
        player: %Player{},
        internal: %Internal{},
        movement_block: movement
      },
      mob: %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 1, 2)},
        unit: unit,
        internal: %Internal{},
        movement_block: movement
      },
      spell: %Spell{
        id: 50,
        school: :shadow,
        duration_ms: 20_000,
        attributes: MapSet.new([:heartbeat_resist]),
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun}]
      },
      context: %CastContext{caster_guid: 1, caster_level: 60, caster_type: :player, heartbeat_sample: 0.5}
    }
  end
end
