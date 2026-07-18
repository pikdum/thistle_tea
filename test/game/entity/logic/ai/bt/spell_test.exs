defmodule ThistleTea.Game.Entity.Logic.AI.BT.SpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.WorldRef

  describe "start_cast/4" do
    test "queues on-next-swing spells instead of starting a cast" do
      spell = %Spell{id: 78, attributes: MapSet.new([:on_next_swing])}
      mob = %Mob{internal: %Internal{}}

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

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

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

      assert mob.internal.casting.channel_ms == 8_000
      assert mob.internal.casting.channel_started?
      assert mob.internal.casting.channel_tick_ms == 2_000
      assert mob.internal.casting.next_channel_tick_at == 3_000
      assert mob.unit.channel_spell == 10
      assert mob.unit.channel_object == 7
      assert mob.internal.broadcast_update? == true

      assert [
               %Event{type: :spell_cast_result, spell_id: 10},
               %Event{type: :spell_go, spell_id: 10},
               %Event{type: :channel_start, spell_id: 10, channel_time_ms: 8_000},
               %Event{type: :object_update, update_type: :values}
             ] = mob.internal.events
    end

    test "applies DBC casting-time modifiers selected by effect class mask" do
      modifier = %Holder{
        spell: %Spell{id: 22_812, spell_family: 7},
        auras: [%AuraData{type: :add_flat_modifier, amount: 1_000, misc_value: 10, class_mask: 0x4}]
      }

      spell = %Spell{id: 5185, spell_family: 7, family_flags_0: 0x4, cast_time_ms: 1_500}
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{auras: [modifier]}, internal: %Internal{}}
      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

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

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>, unit_guid: 1}, 1_000)

      assert mob.internal.casting.cast_time_ms == 0
      assert mob.internal.casting.modifier_holder_ids == [12_043]

      mob = SpellBT.complete_cast(mob, 1_000)

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

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

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
      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

      refute mob.internal.casting.channel_started?
      assert mob.unit.channel_spell in [nil, 0]
      assert mob.internal.events in [nil, []]

      assert {{:running, 1_000}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), 4_000)
      assert mob.internal.casting.channel_started?
      assert mob.unit.channel_spell == 605
      assert Enum.any?(mob.internal.events, &(&1.type == :channel_start))
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
            targets: %Targets{raw: <<0::little-size(16)>>},
            channel_ms: 8_000,
            channel_started?: true,
            ends_at: now - 1
          }
        }
      }

      assert {:success, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert mob.internal.casting == nil
      assert mob.unit.channel_spell == 0

      assert [
               %Event{type: :channel_update, channel_time_ms: 0},
               %Event{type: :object_update, update_type: :values}
             ] = mob.internal.events
    end

    test "channel tick applies the spell hit and advances the next tick" do
      now = 1_000
      spell = %Spell{id: 10, attributes: MapSet.new([:channeled]), effects: []}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: %WorldRef{map_id: 0},
          casting: %Cast{
            spell: spell,
            targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 1},
            channel_ms: 8_000,
            channel_started?: true,
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: now + 8_000
          }
        }
      }

      assert {{:running, delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert delay_ms > 0
      assert mob.internal.casting.next_channel_tick_at > now
      assert mob.internal.events == []
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
            targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 1},
            channel_ms: 10_000,
            channel_started?: true,
            channel_tick_ms: 1_000,
            next_channel_tick_at: now - 1,
            ends_at: now + 10_000
          }
        }
      }

      assert {{:running, _delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert mob.unit.health == 67
    end
  end

  describe "complete_cast/3" do
    test "queues cast result and spell go events before clearing cast state" do
      spell = %Spell{id: 133, effects: []}

      casting = %Cast{
        spell: spell,
        targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 1},
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert mob.internal.casting == nil

      assert [
               %Event{type: :spell_cast_result, spell_id: 133},
               %Event{
                 type: :spell_go,
                 spell_id: 133,
                 source_guid: 1,
                 hit_guids: [1],
                 raw_targets: <<0::little-size(16)>>
               }
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
      targets = %Targets{raw: <<0::little-size(16)>>, unit_guid: 1}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: [modifier]},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}}
      }

      casting = %Cast{spell: spell, targets: targets, started_at: 1_000, ends_at: 1_000}
      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert mob.unit.power1 == 100
      assert mob.unit.auras == []
    end

    test "queues an open-gameobject event for open-lock casts at objects" do
      spell = %Spell{id: 6478, effects: [%Effect{index: 0, type: :open_lock}]}

      casting = %Cast{
        spell: spell,
        targets: %Targets{raw: <<0x4000::little-size(16)>>, object_guid: 0xF110_0001},
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn event ->
               event.type == :open_gameobject and event.target_guid == 0xF110_0001
             end)

      assert Enum.any?(mob.internal.events, fn event ->
               event.type == :spell_go and event.hit_guids == [0xF110_0001]
             end)
    end

    test "queues temporary item enchantments for the targeted item" do
      effect = %Effect{index: 0, type: :enchant_item_temporary, misc_value: 263}
      spell = %Spell{id: 8087, effects: [effect]}

      casting = %Cast{
        spell: spell,
        targets: %Targets{raw: <<0x10::little-size(16)>>, item_guid: 0x4000_002A},
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn event ->
               event.type == :enchant_item and event.target_guid == 0x4000_002A and event.spell == spell and
                 event.effect == effect
             end)
    end

    test "queues self spell hit events after spell go" do
      spell = %Spell{id: 133, school: :fire, effects: [%Effect{type: :school_damage, base_points: 5, die_sides: 0}]}

      casting = %Cast{
        spell: spell,
        targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 1},
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 20, max_health: 20},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert mob.unit.health == 15

      assert [
               %Event{type: :spell_cast_result},
               %Event{type: :spell_go},
               %Event{type: :spell_damage, damage: 5, periodic?: false},
               %Event{type: :object_update, update_type: :values}
             ] = mob.internal.events
    end

    test "queues remote spell delivery events after spell go" do
      spell = %Spell{id: 133, effects: []}

      casting = %Cast{
        spell: spell,
        targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 2},
        ends_at: Time.now()
      }

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 20, max_health: 20},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert [
               %Event{type: :spell_cast_result},
               %Event{type: :spell_go, hit_guids: [2]},
               %Event{type: :deliver_spell, target_guid: 2, spell: ^spell}
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

      targets = %Targets{raw: <<0::little-size(16)>>, item_guid: 22}
      casting = Cast.new(spell, targets, 1_000)

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{summon: 33},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      character = SpellBT.complete_cast(character, casting, 1_000)

      assert Enum.any?(character.internal.events, fn
               %Event{
                 type: :feed_pet,
                 cast_item_guid: 22,
                 target_guid: 33,
                 spell_id: 1539,
                 range_yards: 10.0
               } ->
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

      targets = %Targets{raw: <<0::little-size(16)>>, destination_location: {10.0, 20.0, 30.0}}
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn
               %Event{
                 type: :spawn_area_effect,
                 position: {10.0, 20.0, 30.0},
                 duration_ms: 8_000,
                 spell: %Spell{id: 2120}
               } ->
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

      targets = %Targets{raw: <<0::little-size(16)>>}
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      refute Enum.any?(mob.internal.events, &(&1.type == :spawn_area_effect))
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

      targets = %Targets{raw: <<0::little-size(16)>>}
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {4.0, 5.0, 6.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, &match?(%Event{type: :spawn_area_effect, position: {4.0, 5.0, 6.0}}, &1))
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

      targets = %Targets{raw: <<0::little-size(16)>>, destination_location: {10.0, 20.0, 30.0}}
      casting = Cast.new(spell, targets, 1_000)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: %WorldRef{map_id: 0}, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn
               %Event{type: :spawn_farsight, position: {10.0, 20.0, 30.0}, duration_ms: 60_000} -> true
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

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, now)
      {mob, _events} = Aura.apply_spell(mob, 1, 1, spell, now)
      assert length(mob.unit.auras) == 1

      assert {:success, mob, _bb} = SpellBT.cast_tick(mob, Blackboard.new(), now + 8_001)
      {mob, _events} = Aura.tick(mob, now + 8_001)
      assert mob.unit.auras == []
    end
  end
end
