defmodule ThistleTea.Game.Core.Spell.SpellRefundsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura, as: AuraCore
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.CastResolution.PowerCost
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.State

  setup [:combatants]

  describe "paid cast feedback" do
    test "a cast that loses its required power before launch cannot deliver a refundable hit", context do
      spell = %{context.spell | cast_time_ms: 1_000}
      caster = Casting.start(context.caster, spell, Target.unit(context.target.object.guid), 1_000)
      caster = %{caster | unit: %{caster.unit | power4: 20}, internal: %{caster.internal | events: []}}
      caster = Casting.complete(caster, 2_000)

      assert caster.unit.power4 == 20
      assert caster.internal.casting == nil
      assert Enum.any?(caster.internal.events, &match?(%Effects.SpellCastFailed{reason: :no_power}, &1))
      refute Enum.any?(caster.internal.events, &is_struct(&1, Effects.DeliverSpell))
      refute Enum.any?(caster.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "returns the discounted cost after a charged modifier is consumed", context do
      caster = with_discount(context.caster, :add_flat_modifier, -5)
      {caster, delivery} = launch(caster, context.spell, context.target)
      assert caster.unit.power4 == 60
      assert caster.unit.auras == []
      assert delivery.cast_context.power_cost == %PowerCost{power_type: 3, amount: 40}

      {target, events} = SpellEffect.receive(context.target, delivery.cast_context, delivery.spell, 1_001)
      assert target.unit.health == 100
      assert [%Effects.SpellLogMiss{reason: :immune}, %Effects.AttackOutcome{} = feedback] = events
      assert feedback.power_cost == delivery.cast_context.power_cost
      assert refund(caster, target, feedback).unit.power4 == 93
    end

    test "a consumed clearcasting charge cannot turn an immune cast into free energy", context do
      caster = with_discount(context.caster, :add_pct_modifier, -100)
      caster = %{caster | unit: %{caster.unit | power4: 50}}
      {caster, delivery} = launch(caster, context.spell, context.target)
      assert caster.unit.auras == []
      assert caster.unit.power4 == 50
      assert delivery.cast_context.power_cost == %PowerCost{power_type: 3, amount: 0}
      {target, [_miss, feedback]} = SpellEffect.receive(context.target, delivery.cast_context, delivery.spell, 1_001)
      assert refund(caster, target, feedback).unit.power4 == 50
    end

    test "triggered abilities carry no paid cost", context do
      caster = %{context.caster | unit: %{context.caster.unit | power4: 50}}
      caster = Casting.start_triggered(caster, context.spell, Target.unit(context.target.object.guid), 1_000, nil)
      delivery = Enum.find(caster.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert delivery.cast_context.power_cost == %PowerCost{power_type: nil, amount: 0}
      {target, [_miss, feedback]} = SpellEffect.receive(context.target, delivery.cast_context, delivery.spell, 1_001)
      assert refund(caster, target, feedback).unit.power4 == 50
    end

    test "a multi-effect melee miss produces one refund and no combo points", context do
      {caster, delivery} = launch(context.caster, context.spell, context.target)
      target = %{context.target | unit: %{context.target.unit | auras: []}}
      cast_context = %{delivery.cast_context | hit_chance_bonus: -100}
      :rand.seed(:exsss, {2, 2, 2})
      {target, events} = SpellEffect.receive(target, cast_context, delivery.spell, 1_001)

      assert [%Effects.AttackOutcome{outcome: :miss} = feedback] =
               Enum.filter(events, &is_struct(&1, Effects.AttackOutcome))

      assert Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :miss}, &1))
      refute Enum.any?(events, &is_struct(&1, Effects.AddComboPoints))
      assert refund(caster, target, feedback).unit.power4 == 92
    end

    test "an immune finisher retains its points without a refund", context do
      spell = %{context.spell | attributes: MapSet.new([:ignore_line_of_sight, :finishing_move]), mana_cost: 35}

      caster = %{
        context.caster
        | player: %{context.caster.player | combo_points: 5, field_combo_target: context.target.object.guid}
      }

      {caster, delivery} = launch(caster, spell, context.target)
      {target, [_miss, feedback]} = SpellEffect.receive(context.target, delivery.cast_context, delivery.spell, 1_001)
      caster = refund(caster, target, feedback)
      assert caster.unit.power4 == 65
      assert caster.player.combo_points == 5
    end
  end

  defp combatants(_context) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    {:ok, _owner} = Entity.register(guid)

    caster = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 60,
        class: 4,
        power_type: 3,
        power4: 100,
        max_power4: 100,
        auras: []
      },
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    immunity = %Holder{
      spell: %Spell{id: 642},
      auras: [%AuraCore{type: :school_immunity, misc_value: 1}]
    }

    target = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))},
      unit: %Unit{health: 100, max_health: 100, level: 60, stand_state: 0, auras: [immunity]},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 1752,
      power_type: 3,
      mana_cost: 45,
      school: :physical,
      dmg_class: 2,
      spell_family: 8,
      family_flags_0: 1,
      attributes: MapSet.new([:ignore_line_of_sight, :discount_power_on_miss]),
      effects: [
        %Effect{index: 0, type: :school_damage, base_points: 10, implicit_target_a: :target_enemy},
        %Effect{index: 1, type: :add_combo_points, base_points: 1, implicit_target_a: :target_enemy}
      ]
    }

    %{caster: caster, target: target, spell: spell}
  end

  defp with_discount(caster, type, amount) do
    modifier = %Holder{
      spell: %Spell{id: 90_001, spell_family: 8},
      charges: 1,
      slot: 0,
      auras: [%AuraCore{type: type, amount: amount, misc_value: 14, class_mask: 1}]
    }

    %{caster | unit: %{caster.unit | auras: [modifier]}}
  end

  defp launch(caster, spell, target) do
    caster = caster |> Casting.start(spell, Target.unit(target.object.guid), 1_000) |> Casting.complete(1_000)
    {caster, Enum.find(caster.internal.events, &is_struct(&1, Effects.DeliverSpell))}
  end

  defp refund(caster, target, feedback) do
    EventSink.emit(target, feedback)
    assert_receive {:"$gen_cast", {:attack_outcome, payload}}
    state = %State{guid: caster.object.guid, character: caster}

    assert {:noreply, state, {:continue, :maybe_broadcast_update}} =
             PlayerServer.handle_cast({:attack_outcome, payload}, state)

    state.character
  end
end
