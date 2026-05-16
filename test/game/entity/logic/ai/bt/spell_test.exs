defmodule ThistleTea.Game.Entity.Logic.AI.BT.SpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
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

      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>}, 1_000)

      assert mob.internal.casting.channel_ms == 8_000
      assert mob.internal.casting.channel_tick_ms == 2_000
      assert mob.internal.casting.next_channel_tick_at == 3_000
      assert mob.unit.channel_spell == 10
      assert mob.internal.broadcast_update? == true

      assert [
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
               %Event{type: :channel_update, channel_time_ms: 0},
               %Event{type: :object_update, update_type: :values}
             ] = mob.internal.events
    end

    test "first channel tick marks spell go as sent and advances the next tick" do
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
            channel_go_sent?: false,
            next_channel_tick_at: now - 1,
            ends_at: now + 8_000
          }
        }
      }

      assert {{:running, delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new(), now)
      assert delay_ms > 0
      assert mob.internal.casting.channel_go_sent? == true
      assert mob.internal.casting.next_channel_tick_at > now
      assert [%Event{type: :spell_go, spell_id: 10, hit_guids: [1]}] = mob.internal.events
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
end
