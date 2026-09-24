defmodule ThistleTea.Game.Entity.Logic.FeignDeathTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.FeignDeath
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgFeignDeathResisted
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:character]

  describe "reconcile/4" do
    test "success drops all combat references without Vanish immunity", ctx do
      {character, events} = apply_feign(ctx, %FeignDeath.Attempt{})

      assert FeignDeath.successful?(character)
      assert character.unit.dynamic_flags == 0x20
      refute character.internal.in_combat
      assert character.internal.threat_refs == MapSet.new()
      assert character.internal.auto_shot == nil
      assert character.internal.undetectable_until == nil
      assert Enum.count(events, &is_struct(&1, Effects.DropThreat)) == 2
      assert Enum.any?(events, &is_struct(&1, Effects.FeignDeathApplied))
      assert Enum.any?(events, &is_struct(&1, Effects.CancelAutoRepeat))
    end

    test "resistance retains combat, threat and the death pose", ctx do
      {character, events} = apply_feign(ctx, %FeignDeath.Attempt{resisted?: true})

      refute FeignDeath.successful?(character)
      assert character.unit.dynamic_flags == 0x20
      assert character.internal.in_combat
      assert character.internal.threat_refs == ctx.character.internal.threat_refs
      assert character.internal.auto_shot == nil
      assert character.internal.casting == nil
      assert Enum.any?(events, &is_struct(&1, Effects.FeignDeathResisted))
      refute Enum.any?(events, &is_struct(&1, Effects.DropNearbyThreat))
      refute Enum.any?(events, &is_struct(&1, Effects.FeignDeathApplied))

      character = Aura.break_on_damage(character, 2_000)
      assert character.unit.dynamic_flags == 0x20
      assert length(character.unit.auras) == 1
      assert Hostility.targetable_by?(%{guid: ctx.mob}, character)
    end

    test "success alone removes auras interrupted by stealth or invisibility", ctx do
      sensitive = %Spell{id: 99, aura_interrupt_flags: 0x00100000, effects: [%Effect{type: :apply_aura, aura: :dummy}]}
      {character, _} = Aura.apply_spell(ctx.character, ctx.guid, 50, sensitive, 0)
      ctx = %{ctx | character: character}

      {resisted, _} = apply_feign(ctx, %FeignDeath.Attempt{resisted?: true})
      assert Enum.any?(resisted.unit.auras, &(&1.spell.id == 99))
      {success, _} = apply_feign(ctx, %FeignDeath.Attempt{})
      refute Enum.any?(success.unit.auras, &(&1.spell.id == 99))
    end

    test "movement, expiry and death clear both pose and target protection", ctx do
      {character, _} = apply_feign(ctx, %FeignDeath.Attempt{})
      {moved, _} = Aura.remove_with_interrupt_flags(character, Aura.interrupt_mask(:move), 2_000)
      {expired, _} = Aura.tick(character, 11_000)
      dead = Core.take_damage(character, 500, 2_000)

      for cleaned <- [moved, expired, dead] do
        refute FeignDeath.successful?(cleaned)
        assert Bitwise.band(cleaned.unit.dynamic_flags, 0x20) == 0
      end
    end

    test "a fighting pet keeps the hunter in combat for six seconds", ctx do
      {character, _} = apply_feign(ctx, %FeignDeath.Attempt{pet_in_combat?: true})
      assert FeignDeath.successful?(character)
      assert character.internal.in_combat
      assert character.internal.threat_refs == MapSet.new()
      {before, _} = PlayerCombat.sync(character, Blackboard.new(), 6_999)
      {after_timeout, _} = PlayerCombat.sync(character, Blackboard.new(), 7_000)
      assert before.internal.in_combat
      refute after_timeout.internal.in_combat
    end

    test "creature feigns use the engagement transition", ctx do
      mob = %Mob{object: %Object{guid: ctx.mob}, unit: ctx.character.unit, internal: %Internal{in_combat: true}}
      {mob, events} = Aura.apply_spell(mob, ctx.mob, 50, ctx.spell, 1_000)
      assert FeignDeath.successful?(mob)
      refute mob.internal.in_combat
      assert mob.unit.target == 0
      assert Enum.any?(events, &is_struct(&1, Effects.FeignDeathApplied))
    end
  end

  describe "successful?/1" do
    test "protects from direct NPC targeting while allowing players, pets, helpful spells and area damage", ctx do
      {character, _} = apply_feign(ctx, %FeignDeath.Attempt{})
      npc = %{guid: ctx.mob}
      player = %{guid: 7}
      pet = %{guid: ctx.mob, owner_guid: 7}

      refute Hostility.targetable_by?(npc, character)
      assert Hostility.targetable_by?(player, character)
      assert Hostility.targetable_by?(pet, character)
      assert Hostility.targetable_by?(npc, character, true)
      assert Hostility.targetable_by?(npc, character, false, area?: true)
      assert character.unit.health == 100
    end
  end

  describe "target_lost/3" do
    test "interrupts an incoming cast and stops attacks without resetting other combat", ctx do
      cast = Cast.new(%Spell{id: 133, cast_time_ms: 3_000}, Target.unit(ctx.guid), 0)

      attacker = %{
        ctx.character
        | unit: %{ctx.character.unit | target: ctx.guid},
          internal: %{ctx.character.internal | casting: cast}
      }

      attacker = FeignDeath.target_lost(attacker, ctx.guid, 1_000)
      assert attacker.internal.casting == nil
      assert attacker.internal.auto_shot == nil
      assert attacker.internal.in_combat
      assert Enum.any?(attacker.internal.events, &match?(%Effects.SpellCastFailed{reason: :interrupted}, &1))

      unrelated = %{attacker | internal: %{attacker.internal | casting: cast}}
      assert FeignDeath.target_lost(unrelated, ctx.mob, 1_000) == unrelated
    end
  end

  describe "resisted client feedback" do
    test "encodes the empty packet and sends only to the explicit owner", ctx do
      assert SmsgFeignDeathResisted.to_binary(%SmsgFeignDeathResisted{}) == <<>>
      assert SmsgFeignDeathResisted.opcode() == 0x2B4

      owner =
        spawn(fn ->
          receive do
            message -> send(ctx.test_pid, {:owner, message})
          end
        end)

      EventSink.emit(ctx.character, %Effects.FeignDeathResisted{}, Context.new(owner))
      assert_receive {:owner, {:"$gen_cast", {:send_packet, %SmsgFeignDeathResisted{}}}}
      refute_receive {:"$gen_cast", {:send_packet, %SmsgFeignDeathResisted{}}}
    end
  end

  defp apply_feign(ctx, attempt) do
    context = %CastContext{caster_guid: ctx.guid, caster_level: 50, feign_death: attempt}
    Aura.apply_spell(ctx.character, context, ctx.spell, 1_000)
  end

  defp character(_ctx) do
    guid = System.unique_integer([:positive])
    mob = Guid.from_low_guid(:mob, 1, guid)

    character = %Character{
      object: %Object{guid: guid},
      player: %Player{},
      unit: %Unit{level: 50, health: 100, max_health: 100, target: mob, flags: 0, dynamic_flags: 0x10},
      internal: %Internal{
        in_combat: true,
        threat_refs: MapSet.new([{mob, 1}, {mob + 1, 1}]),
        auto_shot: %{target_guid: mob}
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 5384,
      spell_family: 9,
      family_flags_0: 256,
      duration_ms: 10_000,
      aura_interrupt_flags: 0x3C3C,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :feign_death}]
    }

    %{character: character, guid: guid, mob: mob, spell: spell, test_pid: self()}
  end
end
