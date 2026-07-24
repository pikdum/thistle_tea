defmodule ThistleTea.Game.Entity.Logic.CastPushbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Targets

  @interrupt_pushback 0x02
  @interrupt_cancel 0x10
  @channel_delay 0x4000
  @channel_cancel 0x02

  describe "take_damage/4 hard-cast pushback" do
    test "direct damage delays the cast, capped at the full cast time" do
      caster = casting_character(hard_cast_spell(), 1_000)
      assert caster.internal.casting.ends_at == 4_000

      caster = Core.take_damage(caster, 10, 2_500, source: 99)

      assert caster.internal.casting.ends_at == 5_000
      assert [%Event{type: :spell_delayed, delay_ms: 1_000}] = events_of_type(caster, :spell_delayed)

      caster = clear_events(caster)
      caster = Core.take_damage(caster, 10, 2_600, source: 99)

      assert caster.internal.casting.ends_at == 5_600
      assert [%Event{type: :spell_delayed, delay_ms: 600}] = events_of_type(caster, :spell_delayed)
      assert caster.internal.casting.pushback_count == 2
    end

    test "cancels the cast outright when the spell interrupts on damage" do
      caster = casting_character(%Spell{id: 116, cast_time_ms: 3_000, interrupt_flags: @interrupt_cancel}, 1_000)

      caster = Core.take_damage(caster, 10, 2_000, source: 99)

      assert caster.internal.casting == nil

      assert [%Event{type: :spell_cast_failed, spell_id: 116, reason: :interrupted}] =
               events_of_type(caster, :spell_cast_failed)
    end

    test "periodic damage never pushes back" do
      caster = casting_character(hard_cast_spell(), 1_000)

      caster = Core.take_damage(caster, 10, 2_500, source: 99, periodic: true)

      assert caster.internal.casting.ends_at == 4_000
      assert events_of_type(caster, :spell_delayed) == []
    end

    test "mob casters are unaffected" do
      cast = Cast.new(hard_cast_spell(), %Targets{}, 1_000)

      mob = %Mob{
        object: %Object{guid: 2},
        unit: %Unit{health: 100, max_health: 100, level: 10, auras: []},
        internal: %Internal{casting: cast, events: []}
      }

      mob = Core.take_damage(mob, 10, 2_500, source: 99)

      assert mob.internal.casting.ends_at == 4_000
      assert events_of_type(mob, :spell_delayed) == []
    end

    test "resist-pushback auras can fully prevent the delay" do
      resist = %Holder{
        spell: %Spell{id: 27_827},
        auras: [%AuraData{type: :reduce_pushback, amount: 100}]
      }

      caster = casting_character(hard_cast_spell(), 1_000, auras: [resist])

      caster = Core.take_damage(caster, 10, 2_500, source: 99)

      assert caster.internal.casting.ends_at == 4_000
      assert events_of_type(caster, :spell_delayed) == []
    end
  end

  describe "take_damage/4 channel pushback" do
    test "direct damage shortens the remaining channel and updates the client" do
      caster = channeling_character(channel_spell(@channel_delay), 1_000)
      assert caster.internal.casting.ends_at == 11_000

      caster = Core.take_damage(caster, 10, 2_000, source: 99)

      assert caster.internal.casting.ends_at == 10_000
      assert [%Event{type: :channel_update, channel_time_ms: 8_000}] = events_of_type(caster, :channel_update)
    end

    test "interrupts the channel when the remaining time is exhausted" do
      caster = channeling_character(channel_spell(@channel_delay), 1_000)

      caster = Core.take_damage(caster, 10, 10_900, source: 99)

      assert caster.internal.casting == nil
      assert [%Event{type: :channel_update, channel_time_ms: 0}] = events_of_type(caster, :channel_update)
    end

    test "self-inflicted damage does not shorten the channel" do
      caster = channeling_character(channel_spell(@channel_delay), 1_000)

      caster = Core.take_damage(caster, 10, 2_000, source: 1)

      assert caster.internal.casting.ends_at == 11_000
      assert events_of_type(caster, :channel_update) == []
    end

    test "cancels the channel when its flags interrupt on damage" do
      caster = channeling_character(channel_spell(@channel_cancel), 1_000)

      caster = Core.take_damage(caster, 10, 2_000, source: 99)

      assert caster.internal.casting == nil
    end

    test "asks the channel target to shorten the applied aura" do
      caster = channeling_character(channel_spell(@channel_delay), 1_000, channel_object: 77)

      caster = Core.take_damage(caster, 10, 2_000, source: 99)

      assert [%Event{type: :delay_aura, source_guid: 1, target_guid: 77, spell_id: 15_407, delay_ms: 1_000}] =
               events_of_type(caster, :delay_aura)
    end

    test "mob targets shorten the aura without queueing duration packets" do
      holder = %Holder{
        spell: %Spell{id: 15_407},
        caster_guid: 1,
        slot: 32,
        applied_at: 1_000,
        expires_at: 4_000,
        auras: []
      }

      mob = %Mob{
        object: %Object{guid: 77},
        unit: %Unit{health: 100, max_health: 100, level: 51, auras: [holder]},
        internal: %Internal{events: []}
      }

      mob = Aura.delay_source_spell(mob, 15_407, 1, 1_000, 2_000)

      assert [%Holder{expires_at: 3_000}] = mob.unit.auras
      assert mob.internal.events in [nil, []]
    end

    test "shortens self-channel auras locally" do
      holder = %Holder{
        spell: %Spell{id: 15_407},
        caster_guid: 1,
        slot: 3,
        applied_at: 1_000,
        expires_at: 11_000,
        auras: []
      }

      caster = channeling_character(channel_spell(@channel_delay), 1_000, auras: [holder])

      caster = Core.take_damage(caster, 10, 2_000, source: 99)

      assert [%Holder{expires_at: 10_000}] = caster.unit.auras
      assert [%Event{type: :aura_duration, aura_slot: 3, duration_ms: 8_000}] = events_of_type(caster, :aura_duration)
      assert events_of_type(caster, :delay_aura) == []
    end
  end

  defp hard_cast_spell do
    %Spell{id: 116, cast_time_ms: 3_000, interrupt_flags: @interrupt_pushback}
  end

  defp channel_spell(channel_interrupt_flags) do
    %Spell{
      id: 15_407,
      duration_ms: 10_000,
      attributes: MapSet.new([:channeled]),
      channel_interrupt_flags: channel_interrupt_flags
    }
  end

  defp casting_character(spell, now, opts \\ []) do
    cast = Cast.new(spell, %Targets{}, now)

    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, power_type: 0, auras: Keyword.get(opts, :auras, [])},
      internal: %Internal{casting: cast, events: []}
    }
  end

  defp channeling_character(spell, now, opts \\ []) do
    caster = casting_character(spell, now, opts)
    casting = %{caster.internal.casting | channel_started?: true}
    unit = %{caster.unit | channel_object: Keyword.get(opts, :channel_object, 0), channel_spell: spell.id}
    %{caster | unit: unit, internal: %{caster.internal | casting: casting}}
  end

  defp events_of_type(entity, type) do
    entity.internal.events
    |> List.wrap()
    |> Enum.filter(&(&1.type == type))
  end

  defp clear_events(%{internal: %Internal{} = internal} = entity) do
    %{entity | internal: %{internal | events: []}}
  end
end
