defmodule ThistleTea.Game.Entity.Logic.CastingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.CastResolution.Impact
  alias ThistleTea.Game.Spell.CastResolution.PowerCost
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "start/5" do
    test "queues on-next-swing spells instead of starting a cast" do
      spell = %Spell{id: 78, attributes: MapSet.new([:on_next_swing])}
      mob = %Mob{internal: %Internal{}}

      mob = Casting.start(mob, spell, Target.none(), 1_000)

      assert mob.internal.next_swing_spell == spell
      assert mob.internal.casting == nil
      assert mob.internal.events in [nil, []]
    end

    test "initializes channel tick scheduling and visuals for channeled spells" do
      spell = %Spell{
        id: 10,
        duration_ms: 8_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{amplitude_ms: 2_000}]
      }

      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{target: 7}, internal: %Internal{}}

      mob = Casting.start(mob, spell, Target.none(), 1_000)

      assert mob.internal.casting.channel_ms == 8_000
      assert mob.internal.casting.phase == :channel_tick
      assert mob.internal.casting.channel_tick_ms == 2_000
      assert mob.internal.casting.next_channel_tick_at == 3_000
      assert mob.unit.channel_spell == 10
      assert mob.unit.channel_object == 7
      assert mob.internal.broadcast_update? == true

      assert [
               %Effects.SpellCastResult{spell_id: 10},
               %Effects.SpellGo{spell_id: 10},
               %Effects.ChannelStart{spell_id: 10, channel_time_ms: 8_000}
             ] = mob.internal.events
    end

    test "snapshots one resolution for launch and channel ticks" do
      spell = %Spell{
        id: 5143,
        power_type: 0,
        mana_cost: 10,
        mana_cost_per_second: 5,
        duration_ms: 3_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{implicit_target_a: :caster, amplitude_ms: 1_000}]
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 10, power1: 50, max_power1: 50},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}}
      }

      mob = Casting.start(mob, spell, Target.unit(1), 1_000)
      resolution = mob.internal.casting.resolution

      assert %CastResolution{
               hits: [1],
               costs: %Costs{
                 power: %PowerCost{power_type: 0, amount: 10},
                 channel_power: %PowerCost{power_type: 0, amount: 5}
               },
               impacts: [%Impact{target_guid: 1, target_role: :caster}]
             } = resolution

      assert {:waiting, mob, _delay_ms} = Casting.advance(mob, 2_000)
      assert mob.internal.casting.resolution == resolution
      assert mob.unit.power1 == 35
    end

    test "applies DBC casting-time modifiers selected by effect class mask" do
      modifier = %Holder{
        spell: %Spell{id: 22_812, spell_family: 7},
        auras: [%AuraData{type: :add_flat_modifier, amount: 1_000, misc_value: 10, class_mask: 0x4}]
      }

      spell = %Spell{id: 5185, spell_family: 7, family_flags_0: 0x4, cast_time_ms: 1_500}
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{auras: [modifier]}, internal: %Internal{}}
      mob = Casting.start(mob, spell, Target.none(), 1_000)

      assert mob.internal.casting.cast_time_ms == 2_500
      assert mob.internal.casting.ends_at == 3_500
    end

    test "remembers a charged casting-time modifier after it makes the cast instant" do
      modifier = %Holder{
        spell: %Spell{id: 12_043, spell_family: 3},
        charges: 1,
        slot: 0,
        auras: [%AuraData{type: :add_pct_modifier, amount: -100, misc_value: 10, class_mask: 0x40000000}]
      }

      spell = %Spell{id: 11_360, spell_family: 3, family_flags_0: 0x40000000, cast_time_ms: 6_000}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{auras: [modifier]},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}}
      }

      mob = Casting.start(mob, spell, Target.unit(1), 1_000)

      assert mob.internal.casting.cast_time_ms == 0
      assert mob.internal.casting.modifier_holder_ids == [12_043]

      mob = Casting.complete(mob, 1_000)

      assert mob.unit.auras == []
    end

    test "spends charged modifiers when an affected channel starts" do
      modifier = %Holder{
        spell: %Spell{id: 14_751, spell_family: 6},
        charges: 1,
        slot: 0,
        auras: [%AuraData{type: :add_pct_modifier, amount: -100, misc_value: 14, class_mask: 0}]
      }

      spell = %Spell{
        id: 15_407,
        spell_family: 6,
        mana_cost: 45,
        power_type: 0,
        duration_ms: 3_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{amplitude_ms: 1_000}]
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{power1: 100, max_power1: 100, auras: [modifier]},
        internal: %Internal{}
      }

      mob = Casting.start(mob, spell, Target.none(), 1_000)

      assert mob.unit.power1 == 100
      assert mob.unit.auras == []
    end

    test "waits for a channel's cast time before starting the channel" do
      spell = %Spell{
        id: 605,
        cast_time_ms: 3_000,
        duration_ms: 60_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{implicit_target_a: :caster}]
      }

      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}
      mob = Casting.start(mob, spell, Target.none(), 1_000)

      assert mob.internal.casting.phase == :preparing
      assert mob.unit.channel_spell in [nil, 0]
      assert mob.internal.events in [nil, []]

      assert {{:running, 1_000}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), 4_000)
      assert mob.internal.casting.phase == :channel_tick
      assert mob.unit.channel_spell == 605
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.ChannelStart))
    end
  end

  describe "cast_tick/3" do
    test "ending a channel clears casting without applying a final spell hit" do
      now = 1_000
      spell = %Spell{id: 10, attributes: MapSet.new([:channeled])}

      mob = %Mob{
        object: %Object{guid: 1},
        internal: %Internal{
          casting: %Cast{
            spell: spell,
            targets: Target.none(),
            channel_ms: 8_000,
            phase: :channel_tick,
            resolution: channel_resolution(),
            ends_at: now - 1
          }
        }
      }

      assert {:success, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert mob.internal.casting == nil
      assert mob.unit.channel_spell == 0

      assert [%Effects.ChannelUpdate{channel_time_ms: 0}] = mob.internal.events
    end

    test "channel tick applies periodic trigger effects and advances the next tick" do
      now = 1_000

      spell = %Spell{
        id: 5143,
        duration_ms: 3_000,
        attributes: MapSet.new([:channeled]),
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            trigger_spell_id: 7268,
            implicit_target_a: :caster,
            amplitude_ms: 1_000
          }
        ]
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          casting: %Cast{
            spell: spell,
            targets: Target.unit(1),
            channel_ms: 3_000,
            phase: :channel_tick,
            resolution: channel_resolution(),
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: now + 3_000
          }
        }
      }

      assert {{:running, delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert delay_ms > 0
      assert mob.internal.casting.next_channel_tick_at > now

      assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: 7268}] =
               mob.internal.events
    end

    test "channel tick does not re-apply plain channel auras" do
      now = 5_000

      spell = %Spell{
        id: 12_051,
        duration_ms: 8_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{type: :apply_aura, aura: :mod_power_regen_percent, implicit_target_a: :caster}]
      }

      holder = %Holder{
        spell: spell,
        caster_guid: 1,
        slot: 5,
        applied_at: 1_000,
        expires_at: 9_000,
        auras: []
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, auras: [holder]},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          casting: %Cast{
            spell: spell,
            targets: Target.unit(1),
            channel_ms: 8_000,
            phase: :channel_tick,
            resolution: channel_resolution(),
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: 9_000
          }
        }
      }

      assert {{:running, _delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)

      assert [%Holder{expires_at: 9_000}] = mob.unit.auras
      assert mob.internal.events in [nil, []]
      assert mob.internal.casting.next_channel_tick_at > now
    end

    test "channel tick spends the spell's per-second health cost" do
      now = 1_000

      spell = %Spell{
        id: 11_693,
        power_type: -2,
        mana_cost_per_second: 33,
        attributes: MapSet.new([:channeled]),
        effects: []
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 50, health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          casting: %Cast{
            spell: spell,
            targets: Target.unit(1),
            channel_ms: 10_000,
            phase: :channel_tick,
            resolution: channel_resolution(channel_power: %PowerCost{power_type: -2, amount: 33}),
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: now + 10_000
          }
        }
      }

      assert {{:running, _delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert mob.unit.health == 67
    end

    test "stops when the channel object dies even if the cast target is the caster" do
      now = 1_000
      target_guid = System.unique_integer([:positive])
      Metadata.put(target_guid, %{alive?: false})
      on_exit(fn -> Metadata.delete(target_guid) end)

      spell = %Spell{id: 5143, attributes: MapSet.new([:channeled]), effects: []}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{channel_object: target_guid, channel_spell: spell.id},
        internal: %Internal{
          casting: %Cast{
            spell: spell,
            targets: Target.unit(1),
            channel_ms: 5_000,
            phase: :channel_tick,
            resolution: channel_resolution(),
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: now + 5_000
          }
        }
      }

      assert {:success, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert mob.internal.casting == nil
      assert mob.unit.channel_object == 0
      assert mob.unit.channel_spell == 0
    end

    test "keeps ticking inside the reach-aware hostile channel grace range" do
      now = 1_000
      target_guid = System.unique_integer([:positive])
      world = WorldRef.open(0)
      SpatialHash.insert(:mobs, target_guid, world, 53.0, 0.0, 0.0)
      Metadata.put(target_guid, %{alive?: true, combat_reach: 12.5})

      on_exit(fn ->
        SpatialHash.remove(:mobs, target_guid)
        Metadata.delete(target_guid)
      end)

      spell = %Spell{
        id: 19_304,
        range_yards: 30.0,
        duration_ms: 6_000,
        attributes: MapSet.new([:channeled]),
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :periodic_damage,
            implicit_target_a: :target_enemy,
            amplitude_ms: 1_000
          }
        ]
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{channel_object: target_guid, channel_spell: spell.id, combat_reach: 1.5},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: world,
          casting: %Cast{
            spell: spell,
            targets: Target.unit(1),
            channel_ms: 6_000,
            phase: :channel_tick,
            resolution: channel_resolution(),
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: now + 6_000
          }
        }
      }

      assert {{:running, _delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert %Cast{} = mob.internal.casting
      assert mob.internal.casting.next_channel_tick_at > now
      assert mob.internal.events in [nil, []]
    end
  end

  describe "complete/3" do
    test "stops a target-dependent channel when its only target resists" do
      now = 1_000
      target_guid = 7

      spell = %Spell{
        id: 19_304,
        duration_ms: 6_000,
        attributes: MapSet.new([:channeled]),
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :periodic_damage,
            implicit_target_a: :target_enemy,
            amplitude_ms: 1_000
          }
        ]
      }

      resolution = %{
        channel_resolution()
        | hits: [],
          misses: [%{guid: target_guid, reason: 2}],
          impacts: [],
          followups: %{channel_resolution().followups | packet_hits: [], selected_unit_guid: target_guid}
      }

      casting =
        spell
        |> Cast.new(Target.unit(target_guid), now)
        |> Cast.transition(:launch)
        |> Cast.put_resolution(resolution)
        |> Cast.transition(:impact)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{target: target_guid},
        internal: %Internal{}
      }

      mob = Casting.complete(mob, casting, now)

      assert mob.internal.casting == nil
      assert mob.unit.channel_object == 0
      assert mob.unit.channel_spell == 0

      assert [
               %Effects.ChannelStart{spell_id: 19_304, channel_time_ms: 6_000},
               %Effects.RemoveAura{target_guid: ^target_guid, spell_id: 19_304},
               %Effects.DespawnAreaEffects{spell_id: 19_304},
               %Effects.ChannelUpdate{channel_time_ms: 0}
             ] = mob.internal.events
    end

    test "keeps a self-aura channel active when its selected enemy is not an impact target" do
      now = 1_000
      target_guid = 7

      spell = %Spell{
        id: 5143,
        duration_ms: 5_000,
        attributes: MapSet.new([:channeled]),
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            implicit_target_a: :caster,
            trigger_spell_id: 7268,
            amplitude_ms: 1_000
          }
        ]
      }

      resolution = %{
        channel_resolution()
        | hits: [],
          impacts: [],
          followups: %{channel_resolution().followups | packet_hits: [], selected_unit_guid: target_guid}
      }

      casting =
        spell
        |> Cast.new(Target.unit(target_guid), now)
        |> Cast.transition(:launch)
        |> Cast.put_resolution(resolution)
        |> Cast.transition(:impact)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{target: target_guid},
        internal: %Internal{}
      }

      mob = Casting.complete(mob, casting, now)

      assert %Cast{phase: :channel_tick} = mob.internal.casting
      assert mob.unit.channel_object == target_guid
      assert mob.unit.channel_spell == 5143
      assert [%Effects.ChannelStart{spell_id: 5143, channel_time_ms: 5_000}] = mob.internal.events
    end

    test "queues quest cast credit for successful unit and gameobject targets" do
      unit_guid = Guid.from_low_guid(:mob, 10_978, 1)
      object_guid = Guid.from_low_guid(:game_object, 176_158, 2)
      spell = %Spell{id: 17_166}

      resolution = %{
        channel_resolution()
        | hits: [unit_guid],
          followups: %{channel_resolution().followups | object_guid: object_guid}
      }

      casting = %Cast{
        spell: spell,
        targets: Target.object(object_guid),
        phase: :finish,
        resolution: resolution,
        ends_at: 1_000
      }

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{}
      }

      character = Casting.complete(character, casting, 1_000)

      assert Enum.any?(character.internal.events, fn
               %Effects.QuestCastCredit{target_guids: targets, spell_id: 17_166} ->
                 targets == [object_guid, unit_guid]

               _effect ->
                 false
             end)
    end

    test "dismiss pet transitions the owner instead of the pet target" do
      spell = %Spell{
        id: 2641,
        effects: [%Effect{index: 0, type: :dismiss_pet, implicit_target_a: :pet}]
      }

      resolution = %{
        channel_resolution()
        | hits: [1],
          impacts: [%Impact{target_guid: 1, target_role: :caster}],
          followups: %{channel_resolution().followups | packet_hits: [], selected_unit_guid: 44}
      }

      casting = %Cast{
        spell: spell,
        targets: Target.none(),
        phase: :impact,
        resolution: resolution,
        ends_at: 1_000
      }

      character =
        %Character{
          object: %Object{guid: 1},
          unit: %Unit{health: 100, level: 10},
          player: %Player{},
          internal: %Internal{},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
        }
        |> Companion.activate(:hunter_pet, %EntityRef{guid: 44, entry: 2960, spell_id: 1515})
        |> Casting.complete(casting, 1_000)

      assert character.unit.summon == 0

      assert character.internal.companion ==
               %ThistleTea.Game.Entity.Data.Companion{
                 kind: :hunter_pet,
                 status: {:suspended, 2960, 1515}
               }

      assert Enum.any?(character.internal.events, &match?(%Effects.DismissPet{target_guid: 44}, &1))
    end

    test "queues a take-side outcome when a hostile magic spell is fully resisted" do
      caster_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
      target_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      caster_faction = %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}
      target_faction = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, enemy_group: 12}

      Metadata.put(caster_guid, %{
        alive?: true,
        faction_template: caster_faction,
        faction_can_have_reputation?: false,
        unit_flags: 0,
        level: 60
      })

      Metadata.put(target_guid, %{
        alive?: true,
        faction_template: target_faction,
        faction_can_have_reputation?: false,
        unit_flags: 0,
        level: 60
      })

      on_exit(fn ->
        Metadata.delete(caster_guid)
        Metadata.delete(target_guid)
      end)

      hit_penalty = %Holder{
        spell: %Spell{id: 1},
        auras: [%AuraData{type: :mod_spell_hit_chance, amount: -100}]
      }

      spell = %Spell{
        id: 116,
        school: :frost,
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
      }

      casting = %Cast{
        spell: spell,
        targets: Target.unit(target_guid),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60, auras: [hit_penalty]},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      :rand.seed(:exsss, {1, 2, 3})
      mob = Casting.complete(mob, casting, 1_000)

      assert [
               %Effects.SpellCastResult{spell_id: 116},
               %Effects.SpellGo{hit_guids: [], misses: [%{guid: ^target_guid, reason: 2}]},
               %Effects.DeliverSpellOutcome{
                 source_guid: ^caster_guid,
                 target_guid: ^target_guid,
                 spell: ^spell,
                 outcome: :resist
               }
             ] = mob.internal.events
    end

    test "applies the victim's school-masked spell hit modifier from metadata" do
      caster_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
      target_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      caster_faction = %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}
      target_faction = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, enemy_group: 12}

      Metadata.put(caster_guid, %{
        alive?: true,
        faction_template: caster_faction,
        faction_can_have_reputation?: false,
        unit_flags: 0,
        level: 60
      })

      Metadata.put(target_guid, %{
        alive?: true,
        faction_template: target_faction,
        faction_can_have_reputation?: false,
        unit_flags: 0,
        level: 60,
        attacker_spell_hit_chance: [{0x7E, -2}]
      })

      on_exit(fn ->
        Metadata.delete(caster_guid)
        Metadata.delete(target_guid)
      end)

      spell = %Spell{
        id: 133,
        school: :fire,
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
      }

      casting = %Cast{
        spell: spell,
        targets: Target.unit(target_guid),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: caster_guid},
        unit: %Unit{level: 60},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      :rand.seed(:exsss, {1, 1, 66})
      missed = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(missed.internal.events, fn
               %Effects.SpellGo{hit_guids: [], misses: [%{guid: ^target_guid, reason: 2}]} -> true
               _event -> false
             end)

      Metadata.update(target_guid, %{attacker_spell_hit_chance: []})

      :rand.seed(:exsss, {1, 1, 66})
      hit = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(hit.internal.events, fn
               %Effects.SpellGo{hit_guids: [^target_guid], misses: []} -> true
               _event -> false
             end)
    end

    test "queues cast result and spell go events before clearing cast state" do
      spell = %Spell{id: 133, effects: []}

      casting = %Cast{
        spell: spell,
        targets: Target.unit(1),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert mob.internal.casting == nil

      assert [
               %Effects.SpellCastResult{spell_id: 133},
               %Effects.SpellGo{spell_id: 133, source_guid: 1, hit_guids: [1], targets: %Target{}}
             ] = mob.internal.events
    end

    test "spends charged spell modifiers after an affected successful cast" do
      modifier = %Holder{
        spell: %Spell{id: 14_751, spell_family: 6},
        charges: 1,
        slot: 0,
        auras: [%AuraData{type: :add_pct_modifier, amount: -100, misc_value: 14, class_mask: 0}]
      }

      spell = %Spell{id: 2061, spell_family: 6, mana_cost: 10, power_type: 0}
      targets = Target.unit(1)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: [modifier]},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}}
      }

      casting = %Cast{spell: spell, targets: targets, started_at: 1_000, ends_at: 1_000, modifier_holder_ids: [14_751]}
      mob = Casting.complete(mob, casting, 1_000)

      assert mob.unit.power1 == 100
      assert mob.unit.auras == []
    end

    test "queues an open-gameobject event for open-lock casts at objects" do
      spell = %Spell{id: 6478, effects: [%Effect{index: 0, type: :open_lock}]}

      casting = %Cast{
        spell: spell,
        targets: Target.object(0xF110_0001, :locked),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn event ->
               is_struct(event, Effects.OpenGameObject) and event.target_guid == 0xF110_0001
             end)

      assert Enum.any?(mob.internal.events, fn event ->
               is_struct(event, Effects.SpellGo) and event.hit_guids == [0xF110_0001]
             end)
    end

    test "queues temporary item enchantments for the targeted item" do
      effect = %Effect{index: 0, type: :enchant_item_temporary, misc_value: 263}
      spell = %Spell{id: 8087, effects: [effect]}

      casting = %Cast{
        spell: spell,
        targets: Target.item(0x4000_002A),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn event ->
               is_struct(event, Effects.EnchantItem) and event.target_guid == 0x4000_002A and event.spell == spell and
                 event.effect == effect
             end)
    end

    test "queues self spell hit events after spell go" do
      spell = %Spell{id: 133, school: :fire, effects: [%Effect{type: :school_damage, base_points: 5, die_sides: 0}]}

      casting = %Cast{
        spell: spell,
        targets: Target.unit(1),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 20, max_health: 20},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert mob.unit.health == 15

      assert [
               %Effects.SpellCastResult{},
               %Effects.SpellGo{},
               %Effects.SpellDamage{damage: 5, periodic?: false}
             ] = mob.internal.events
    end

    test "queues remote spell delivery events after spell go" do
      spell = %Spell{id: 133, effects: []}

      casting = %Cast{
        spell: spell,
        targets: Target.unit(2),
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 20, max_health: 20},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert [
               %Effects.SpellCastResult{},
               %Effects.SpellGo{hit_guids: [2]},
               %Effects.DeliverSpell{target_guid: 2, spell: ^spell}
             ] = mob.internal.events
    end
  end

  describe "Feed Pet" do
    test "queues the DBC trigger spell for the selected food item and active pet" do
      spell = %Spell{
        id: 6991,
        range_yards: 10.0,
        effects: [%Effect{index: 0, type: :feed_pet, trigger_spell_id: 1539}]
      }

      targets = Target.item(22)
      casting = Cast.new(spell, targets, 1_000)

      character =
        %Character{
          object: %Object{guid: 1},
          unit: %Unit{},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
        }
        |> Companion.activate(:hunter_pet, %EntityRef{guid: 33, entry: 1, spell_id: 1515})

      character = Casting.complete(character, casting, 1_000)

      assert Enum.any?(character.internal.events, fn
               %Effects.FeedPet{cast_item_guid: 22, target_guid: 33, spell_id: 1539, range_yards: 10.0} ->
                 true

               _ ->
                 false
             end)
    end
  end

  describe "persistent area auras" do
    test "ground-targeted cast queues a spawn_area_effect event" do
      spell = %Spell{
        id: 2120,
        name: "Flamestrike",
        school: :fire,
        duration_ms: 8_000,
        effects: [
          %Effect{index: 0, type: :school_damage, base_points: 50, die_sides: 0, radius_yards: 5.0},
          %Effect{
            index: 1,
            type: :persistent_area_aura,
            aura: :periodic_damage,
            base_points: 10,
            die_sides: 0,
            amplitude_ms: 2_000,
            radius_yards: 5.0
          }
        ]
      }

      targets = Target.at({10.0, 20.0, 30.0})
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn
               %Effects.SpawnAreaEffect{position: {10.0, 20.0, 30.0}, duration_ms: 8_000, spell: %Spell{id: 2120}} ->
                 true

               _ ->
                 false
             end)
    end

    test "cast without ground location does not queue area effects" do
      spell = %Spell{
        id: 2120,
        name: "Flamestrike",
        school: :fire,
        duration_ms: 8_000,
        effects: [
          %Effect{index: 1, type: :persistent_area_aura, aura: :periodic_damage, base_points: 10, die_sides: 0}
        ]
      }

      targets = Target.none()
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      refute Enum.any?(mob.internal.events, &is_struct(&1, Effects.SpawnAreaEffect))
    end

    test "caster-centered persistent aura uses the caster position without a ground target" do
      spell = %Spell{
        id: 26_573,
        name: "Consecration",
        school: :holy,
        duration_ms: 8_000,
        effects: [
          %Effect{
            index: 0,
            type: :persistent_area_aura,
            aura: :periodic_damage,
            base_points: 8,
            amplitude_ms: 1_000,
            radius_yards: 8.0,
            implicit_target_a: :caster_destination,
            implicit_target_b: :aoe_enemy_at_dest
          }
        ]
      }

      targets = Target.none()
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {4.0, 5.0, 6.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, &match?(%Effects.SpawnAreaEffect{position: {4.0, 5.0, 6.0}}, &1))
    end
  end

  describe "farsight" do
    test "DBC farsight effects queue a remote viewpoint at the destination" do
      spell = %Spell{
        id: 6196,
        name: "Far Sight",
        duration_ms: 60_000,
        effects: [%Effect{index: 0, type: :add_farsight}]
      }

      targets = Target.at({10.0, 20.0, 30.0})
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = Casting.complete(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn
               %Effects.SpawnFarsight{position: {10.0, 20.0, 30.0}, duration_ms: 60_000} -> true
               _ -> false
             end)
    end
  end

  describe "channel auras" do
    test "a completed self channel leaves its aura to expire after the final tick" do
      spell = %Spell{
        id: 12_051,
        name: "Evocation",
        duration_ms: 8_000,
        attributes: MapSet.new([:channeled]),
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :mod_power_regen_percent,
            base_points: 1499,
            die_sides: 1,
            base_dice: 1
          }
        ]
      }

      now = 1_000

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}}
      }

      mob = Casting.start(mob, spell, Target.none(), now)
      {mob, _events} = Aura.apply_spell(mob, 1, 1, spell, now)
      assert length(mob.unit.auras) == 1

      assert {:success, mob, _bb} = SpellBT.cast_tick(mob, Blackboard.new(), now + 8_001)
      {mob, _events} = Aura.tick(mob, now + 8_001)
      assert mob.unit.auras == []
    end
  end

  defp channel_resolution(opts \\ []) do
    %CastResolution{
      hits: [1],
      misses: [],
      costs: %Costs{
        power: %PowerCost{power_type: nil, amount: 0},
        channel_power: Keyword.get(opts, :channel_power, %PowerCost{power_type: nil, amount: 0}),
        reagents: [],
        ammo: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      impacts: [%Impact{target_guid: 1, target_role: :caster}],
      followups: %Followups{
        packet_hits: [1],
        selected_unit_guid: 1,
        object_guid: nil,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }
  end
end
