defmodule ThistleTea.Game.Entity.Logic.AI.BT.SpellTest do
  use ExUnit.Case, async: true

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

  describe "start_cast/4" do
    test "queues on-next-swing spells instead of starting a cast" do
      spell = %Spell{id: 78, attributes: MapSet.new([:on_next_swing])}
      mob = %Mob{internal: %Internal{}}

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

      assert mob.internal.next_swing_spell == spell
      assert mob.internal.casting == nil
      assert [%Event{type: :spell_cast_result, spell_id: 78}] = mob.internal.events
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
            ends_at: now - 1
          }
        }
      }

      assert {:success, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert mob.internal.casting == nil
      assert mob.unit.channel_spell == 0

      assert [
               %Event{type: :despawn_area_effects, spell_id: 10},
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
          map: 0,
          casting: %Cast{
            spell: spell,
            targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 1},
            channel_ms: 8_000,
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
        internal: %Internal{map: 0, casting: casting}
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
        internal: %Internal{map: 0, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert Enum.any?(mob.internal.events, fn event ->
               event.type == :open_gameobject and event.target_guid == 0xF110_0001
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
        internal: %Internal{map: 0, casting: casting}
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
        internal: %Internal{map: 0, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      assert [
               %Event{type: :spell_cast_result},
               %Event{type: :spell_go, hit_guids: [2]},
               %Event{type: :deliver_spell, target_guid: 2, spell: ^spell}
             ] = mob.internal.events
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
        internal: %Internal{map: 0, casting: casting}
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
        internal: %Internal{map: 0, casting: casting}
      }

      mob = SpellBT.complete_cast(mob, casting, 1_000)

      refute Enum.any?(mob.internal.events, &(&1.type == :spawn_area_effect))
    end
  end

  describe "channel auras" do
    test "stopping a self channel removes the channel spell's auras" do
      spell = %Spell{
        id: 12_051,
        name: "Evocation",
        duration_ms: 8_000,
        attributes: MapSet.new([:channeled]),
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_power_regen_percent, base_points: 1499, die_sides: 1}
        ]
      }

      now = 1_000

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{map: 0}
      }

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, now)
      {mob, _events} = Aura.apply_spell(mob, 1, 1, spell, now)
      assert length(mob.unit.auras) == 1

      assert {:success, mob, _bb} = SpellBT.cast_tick(mob, Blackboard.new(), now + 8_001)
      assert mob.unit.auras == []
    end
  end
end
