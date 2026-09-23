defmodule ThistleTea.Game.Entity.Logic.SpellInterruptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellInterrupt
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:caster]

  describe "apply/4" do
    test "interrupts a preparing cast and projects the owner's school cooldowns", context do
      %{entity: entity, spell: spell, interrupt: interrupt, attacker: attacker} = context
      casting = Casting.start(entity, spell, Target.self(entity.object.guid), 1_000)
      {stopped, events} = SpellInterrupt.apply(casting, attacker, interrupt, 2_000)
      assert stopped.internal.casting == nil
      assert Cooldowns.school_locked?(stopped, 4, 11_999)
      refute Cooldowns.school_locked?(stopped, 4, 12_000)
      refute Cooldowns.school_locked?(stopped, 16, 2_000)
      assert [%Effects.SpellInterrupted{spell_id: 2139, interrupted_spell_id: 133}] = events
      stopped |> Effects.enqueue(events) |> EventSink.emit_pending(Context.new(self()))
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: 133, reason: 0x23}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellFailure{spell: 133}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellCooldown{cooldowns: [{133, 10_000}]}}}
      assert {unchanged, []} = SpellInterrupt.apply(stopped, attacker, interrupt, 3_000)
      assert unchanged.internal.cooldowns == stopped.internal.cooldowns
    end

    test "removes a channel aura and prevents its remaining healing ticks", context do
      %{entity: entity, spell: spell, interrupt: interrupt, attacker: attacker} = context

      channel = %{
        spell
        | cast_time_ms: 0,
          duration_ms: 10_000,
          channel_interrupt_flags: 4,
          attributes: MapSet.new([:channeled]),
          effects: [
            %Effect{
              type: :apply_aura,
              aura: :obs_mod_health,
              base_points: 7,
              amplitude_ms: 2_000,
              implicit_target_a: :caster
            }
          ]
      }

      casting = Casting.start(entity, channel, Target.self(entity.object.guid), 1_000)
      assert Aura.has_spell?(casting, channel.id)
      {stopped, _events} = SpellInterrupt.apply(casting, attacker, interrupt, 2_000)
      refute Aura.has_spell?(stopped, channel.id)
      assert stopped.unit.channel_spell == 0
      assert stopped.unit.channel_object == 0
      assert Enum.count(stopped.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1)) == 1
      {later, _events} = Aura.tick(stopped, 15_000)
      assert later.unit.health == entity.unit.health
    end

    test "releases owned objects through channel cancellation", context do
      %{entity: entity, spell: spell, interrupt: interrupt, attacker: attacker} = context
      spell = %{spell | channel_interrupt_flags: 4}
      casting = Casting.start_game_object_channel(entity, 777, spell, 30_000, 1_000)
      casting = %{casting | internal: %{casting.internal | channel_game_object_owned?: true}}
      {stopped, _events} = SpellInterrupt.apply(casting, attacker, interrupt, 2_000)
      assert stopped.internal.channel_game_object_guid == nil
      assert Enum.any?(stopped.internal.events, &match?(%Effects.DespawnEntity{target_guid: 777}, &1))
    end

    test "silence-immune creatures can be interrupted without a school lock", context do
      %{entity: entity, spell: spell, interrupt: interrupt, attacker: attacker} = context

      mob = %Mob{
        object: entity.object,
        unit: entity.unit,
        movement_block: entity.movement_block,
        internal: %Internal{creature: %Creature{mechanic_immune_mask: 256}}
      }

      casting = Casting.start(mob, spell, Target.self(mob.object.guid), 1_000)
      {stopped, [%Effects.SpellInterrupted{}]} = SpellInterrupt.apply(casting, attacker, interrupt, 2_000)
      assert stopped.internal.casting == nil
      refute Cooldowns.school_locked?(stopped, 4, 2_000)
    end

    test "zero-duration interrupts cancel without locking and dead targets remain untouched", context do
      %{entity: entity, spell: spell, interrupt: interrupt, attacker: attacker} = context
      casting = Casting.start(entity, spell, Target.self(entity.object.guid), 1_000)
      {stopped, [_event]} = SpellInterrupt.apply(casting, attacker, %{interrupt | duration_ms: 0}, 2_000)
      assert stopped.internal.casting == nil
      assert stopped.internal.cooldowns == %{}
      dead = %{casting | unit: %{casting.unit | health: 0}}
      assert SpellInterrupt.apply(dead, attacker, interrupt, 2_000) == {dead, []}
    end
  end

  describe "interruptible?/1" do
    test "requires a susceptible active cast or channel", %{spell: spell} do
      assert SpellInterrupt.interruptible?(Cast.new(spell, Target.self(1), 0))
      channel = %Cast{phase: :channel_tick, spell: %{spell | channel_interrupt_flags: 4}}
      assert SpellInterrupt.interruptible?(channel)

      for cast <- [
            %{channel | spell: %{spell | channel_interrupt_flags: 0}},
            Cast.new(%{spell | cast_time_ms: 0}, Target.self(1), 0),
            Cast.new(%{spell | interrupt_flags: 0}, Target.self(1), 0),
            Cast.new(%{spell | prevention_type: 0}, Target.self(1), 0),
            %{Cast.new(spell, Target.self(1), 0) | phase: :impact},
            %{Cast.new(spell, Target.self(1), 0) | phase: :finish}
          ] do
        refute SpellInterrupt.interruptible?(cast)
      end
    end
  end

  defp caster(_context) do
    spell = %Spell{id: 133, school: :fire, prevention_type: 1, interrupt_flags: 2, cast_time_ms: 3_000}

    entity = %Character{
      object: %Object{guid: System.unique_integer([:positive]) + 84_000_000},
      unit: %Unit{health: 100, max_health: 1_000, level: 50},
      player: %Player{},
      internal: %Internal{spellbook: %{133 => spell, 116 => %Spell{id: 116, school: :frost}}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{
      entity: entity,
      spell: spell,
      interrupt: %Spell{id: 2139, duration_ms: 10_000},
      attacker: %CastContext{caster_guid: 999}
    }
  end
end
