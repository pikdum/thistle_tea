defmodule ThistleTea.Game.Entity.SpellContactTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Combat
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  setup [:actors]

  describe "prepare/4 and apply_prepared/3" do
    test "an undetected immune Sap leaves both owners peaceful", ctx do
      prepared = SpellReception.prepare(ctx.mob, ctx.context, ctx.sap, 0)
      assert prepared.resolution.outcome == :immune
      refute SpellReception.starts_combat?(prepared)
      {target, events} = SpellReception.apply_prepared(ctx.mob, prepared, 0)
      assert target.unit.health == ctx.mob.unit.health
      assert [%Effects.SpellLogMiss{reason: :immune}] = events

      assert {:noreply, target, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_spell, ctx.context, ctx.sap}, ctx.mob)

      refute target.internal.in_combat
      assert target.internal.threat == %{}
      assert target.internal.loot.tapped_by == nil
      refute_receive {:"$gen_cast", {:spell_contact, _}}
      cancel_tick(target)
    end

    test "a detected immune Sap engages players and alerts the defensive pet", ctx do
      target = %{ctx.player | unit: %{ctx.player.unit | level: 60}}
      target = Pvp.toggle(target, true, Time.now())
      Entity.register(ctx.pet)
      on_exit(fn -> Entity.unregister(ctx.pet) end)
      companion = %Companion{kind: :hunter_pet, status: {:active, %EntityRef{guid: ctx.pet, entry: 1, spell_id: 1}}}
      target = %{target | internal: %{target.internal | companion: companion}}

      assert {:noreply, state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_spell, ctx.context, ctx.sap}, %State{
                 guid: target.object.guid,
                 character: target
               })

      assert state.character.internal.in_combat
      assert_receive {:owner_attacked, source} when source == ctx.caster.object.guid
      assert_receive {:"$gen_cast", {:spell_contact, contact}}
      assert contact.decision.combat?
      refute contact.decision.break_stealth?
      caster = Combat.apply_caster(ctx.caster, contact)
      assert caster.internal.in_combat
      assert AuraLogic.has_aura?(caster, :mod_stealth)
      assert_receive {:"$gen_cast", {:pvp_contact, pvp}}
      assert Pvp.active?(EventSink.emit(caster, pvp))
      cancel_tick(state)
    end

    test "an undetected miss neither flags players nor alerts the pet", ctx do
      target = Pvp.toggle(ctx.player, true, Time.now())
      Entity.register(ctx.pet)
      on_exit(fn -> Entity.unregister(ctx.pet) end)
      companion = %Companion{kind: :hunter_pet, status: {:active, %EntityRef{guid: ctx.pet, entry: 1, spell_id: 1}}}
      target = %{target | internal: %{target.internal | companion: companion}}

      assert {:noreply, state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:receive_spell, ctx.context, ctx.sap}, %State{
                 guid: target.object.guid,
                 character: target
               })

      refute state.character.internal.in_combat
      refute_receive {:owner_attacked, _}
      refute_receive {:"$gen_cast", {:spell_contact, _}}
      refute_receive {:"$gen_cast", {:pvp_contact, _}}
      cancel_tick(state)
    end

    test "failure-breaks-stealth provokes an undetecting creature", ctx do
      spell = %{ctx.sap | attributes: MapSet.new([:failure_breaks_stealth, :no_threat])}

      assert {:noreply, mob, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_spell, ctx.context, spell}, ctx.mob)

      assert mob.internal.in_combat
      assert_receive {:"$gen_cast", {:spell_contact, contact}}
      caster = Combat.apply_caster(ctx.caster, contact)
      assert caster.internal.in_combat
      refute AuraLogic.has_aura?(caster, :mod_stealth)
      cancel_tick(mob)
    end

    test "the prepared outcome cannot reroll after the recipient's aura changes", ctx do
      prepared = SpellEffect.prepare(ctx.mob, ctx.context, ctx.sap)
      target = %{ctx.mob | unit: %{ctx.mob.unit | auras: []}}
      assert {^target, [%Effects.SpellLogMiss{reason: :immune}]} = SpellEffect.apply_prepared(target, prepared, 0)
    end

    test "a projectile uses current concealment while an instant uses its launch snapshot", ctx do
      context = %{ctx.context | caster_detection: %{stealthed?: false}}
      Metadata.put(ctx.caster.object.guid, ctx.context.caster_detection)
      instant = SpellReception.prepare(ctx.mob, context, ctx.sap, 0)
      projectile = SpellReception.prepare(ctx.mob, context, %{ctx.sap | speed: 20.0}, 0)
      assert SpellReception.starts_combat?(instant)
      refute SpellReception.starts_combat?(projectile)
    end

    test "no-initial-threat damage engages and lethal damage still claims the loot", ctx do
      spell = %Spell{
        id: 2,
        school: :fire,
        attributes: MapSet.new([:no_initial_threat]),
        effects: [%Effect{index: 0, type: :school_damage, base_points: 20, implicit_target_a: :target_enemy}]
      }

      context = %{ctx.context | caster_detection: %{stealthed?: false}, spell: spell}

      for health <- [100, 1] do
        target = %{ctx.mob | unit: %{ctx.mob.unit | health: health, auras: []}}
        prepared = SpellReception.prepare(target, context, spell, 0)
        refute SpellReception.starts_combat?(prepared)

        assert {:noreply, mob, {:continue, :maybe_broadcast}} =
                 MobServer.handle_cast({:receive_spell, context, spell}, target)

        assert mob.internal.loot.tapped_by,
               inspect({mob.unit.health, mob.internal.in_combat, mob.internal.events}, limit: 15)

        assert mob.internal.loot.tapped_by.player == ctx.caster.object.guid
        assert mob.internal.in_combat == health > 20
        cancel_tick(mob)
      end
    end

    test "owner-local combat contacts use the supplied owner context", ctx do
      contact = %Effects.SpellContact{
        target_guid: ctx.caster.object.guid,
        other_guid: ctx.mob.object.guid,
        now: 0,
        decision: %Combat{combat?: true}
      }

      assert EventSink.emit(ctx.caster, contact, Context.new(self())) == ctx.caster
      assert_receive {:"$gen_cast", {:spell_contact, ^contact}}
    end

    test "instant proc damage lands without starting combat for either owner", ctx do
      spell = %Spell{
        id: 4,
        school: :fire,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 20, implicit_target_a: :target_enemy}]
      }

      context = %{
        ctx.context
        | caster_detection: %{stealthed?: false},
          triggered_by_aura?: true,
          triggered_by_proc?: true,
          spell: spell
      }

      target = %{ctx.mob | unit: %{ctx.mob.unit | auras: []}}

      assert {:noreply, mob, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_spell, context, spell}, target)

      assert mob.unit.health == 80
      refute mob.internal.in_combat
      refute_receive {:"$gen_cast", {:spell_contact, _}}
      cancel_tick(mob)
    end

    test "a channeled first damage tick enters combat and preserves lethal-tick credit", ctx do
      spell = %Spell{
        id: 3,
        school: :physical,
        duration_ms: 5_000,
        attributes: MapSet.new([:no_initial_threat, :channeled]),
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_damage,
            amplitude_ms: 1_000,
            base_points: 20,
            implicit_target_a: :target_enemy
          }
        ]
      }

      on_exit(fn -> World.remove_position(ctx.mob) end)

      for health <- [100, 1] do
        target = %{ctx.mob | unit: %{ctx.mob.unit | health: health, auras: []}}
        {target, _events} = AuraLogic.apply_spell(target, ctx.caster.object.guid, 60, spell, Time.now() - 1_001)
        refute target.internal.in_combat
        target = BT.init(target, BT.action(fn entity, blackboard, _context -> {:failure, entity, blackboard} end))
        assert {:noreply, mob, {:continue, :maybe_broadcast}} = MobServer.handle_info(:ai_tick, target)
        assert mob.unit.health < health
        assert mob.internal.loot.tapped_by.player == ctx.caster.object.guid
        assert mob.internal.in_combat == health > 20
        assert_receive {:"$gen_cast", {:spell_contact, %Effects.SpellContact{decision: %{combat?: true}}}}
        cancel_tick(mob)
        Visibility.leave_entity(mob)
      end
    end
  end

  defp actors(_context) do
    source = System.unique_integer([:positive])
    target = System.unique_integer([:positive])
    mob_guid = Guid.from_low_guid(:mob, 38, System.unique_integer([:positive]))
    pet = Guid.from_low_guid(:pet, 1, System.unique_integer([:positive]))
    world = WorldRef.open(0)
    stealth = %Holder{spell: %Spell{id: 1786}, auras: [%Aura{type: :mod_stealth, amount: 300}]}
    immune = %Holder{spell: %Spell{id: 1022}, auras: [%Aura{type: :school_immunity, misc_value: 1}]}

    caster = %Character{
      object: %Object{guid: source},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: [stealth]},
      player: %Player{},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {4.5, 0.0, 0.0, 0.0}}
    }

    player = %Character{
      object: %Object{guid: target},
      unit: %Unit{health: 100, max_health: 100, level: 4, auras: [immune]},
      player: %Player{},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    mob = %Mob{
      object: %Object{guid: mob_guid},
      unit: player.unit,
      internal: %{player.internal | threat: %{}, loot: %Loot{}},
      movement_block: player.movement_block
    }

    context = %CastContext{
      caster_guid: source,
      caster_level: 60,
      caster_position: {world, 4.5, 0.0, 0.0},
      caster_detection: %{stealthed?: true, stealth_skill: 300, level: 60, player?: true},
      target_role: :other,
      target_hostile?: true
    }

    sap = %Spell{
      id: 11_297,
      school: :physical,
      spell_family: 8,
      family_flags_0: 0x80,
      duration_ms: 45_000,
      attributes: MapSet.new([:not_in_combat, :only_peaceful_targets]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy, base_points: 0}]
    }

    Entity.register(source)

    on_exit(fn ->
      Entity.unregister(source)
      Metadata.delete(source)
    end)

    %{caster: caster, player: player, mob: mob, context: context, sap: sap, pet: pet}
  end

  defp cancel_tick(%{player_tick_ref: ref}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_tick(%{internal: %{ai_tick_ref: ref}}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_tick(_state), do: :ok
end
