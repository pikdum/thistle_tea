defmodule ThistleTea.Game.Entity.Logic.TriggeredChannelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:caster]

  describe "start_triggered/5" do
    test "creates a real channel without paying normal cast costs", %{character: character, spell: spell} do
      casting = Casting.start_triggered(character, spell, Target.self(character.object.guid), 1_000, nil)

      assert %Cast{triggered?: true, phase: :channel_tick} = casting.internal.casting
      assert casting.unit.channel_spell == spell.id
      assert casting.unit.power1 == 100
      assert casting.internal.cooldowns == %{}
      assert Aura.has_spell?(casting, spell.id)
      assert Enum.any?(casting.internal.events, &is_struct(&1, Effects.ChannelStart))
      refute Enum.any?(casting.internal.events, &is_struct(&1, Effects.SpellCastResult))
      refute Enum.any?(casting.internal.events, &is_struct(&1, Effects.ConsumeReagents))
    end

    test "heals every two seconds and expires after five ticks", %{character: character, spell: spell} do
      casting = Casting.start_triggered(character, spell, Target.self(character.object.guid), 1_000, nil)
      {waiting, _} = Aura.tick(casting, 2_999)
      assert waiting.unit.health == 100

      final =
        Enum.reduce([3_000, 5_000, 7_000, 9_000, 11_000], casting, fn now, entity ->
          {entity, events} = Aura.tick(entity, now)
          assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: 70}, &1))
          assert Enum.any?(events, &match?(%Effects.EmoteState{emote_id: 398}, &1))
          entity
        end)

      assert final.unit.health == 450
      refute Aura.has_spell?(final, spell.id)
      assert {:finished, final} = Casting.advance(final, 11_000)
      assert final.internal.casting == nil
      assert final.unit.channel_spell == 0
      assert Enum.any?(final.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1))
      {later, _} = Aura.tick(final, 20_000)
      assert later.unit.health == 450
    end

    test "periodic damage removes the aura and channel together", %{character: character, spell: spell} do
      casting = Casting.start_triggered(character, spell, Target.self(character.object.guid), 1_000, nil)
      damaged = Core.take_damage(casting, 10, 1_500, periodic: true)
      assert damaged.unit.health == 90
      assert damaged.internal.casting == nil
      assert damaged.unit.channel_spell == 0
      refute Aura.has_spell?(damaged, spell.id)
      assert Enum.any?(damaged.internal.events, &match?(%Effects.EmoteState{emote_id: 0}, &1))
      assert Enum.count(damaged.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1)) == 1
    end

    test "canceling a channel removes its recovery without restarting it", %{character: character, spell: spell} do
      casting = Casting.start_triggered(character, spell, Target.self(character.object.guid), 1_000, nil)
      canceled = Casting.cancel(casting, 1_500)
      assert canceled.internal.casting == nil
      assert canceled.unit.channel_spell == 0
      refute Aura.has_spell?(canceled, spell.id)
      assert Enum.count(canceled.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1)) == 1
      {later, _} = Aura.tick(canceled, 20_000)
      assert later.unit.health == 100
    end
  end

  defp caster(_context) do
    guid = System.unique_integer([:positive]) + 80_000_000

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 1_000, power1: 100, max_power1: 100, level: 50, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 20_578,
      script_name: "spell_cannibalize_aura",
      attributes: MapSet.new([:channeled]),
      duration_ms: 10_000,
      aura_interrupt_flags: 2,
      channel_interrupt_flags: 0x3C0E,
      mana_cost: 50,
      mana_cost_per_second: 10,
      power_type: 0,
      gcd_ms: 1_500,
      recovery_time_ms: 60_000,
      reagents: [{1, 1}],
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

    %{character: character, spell: spell}
  end
end
