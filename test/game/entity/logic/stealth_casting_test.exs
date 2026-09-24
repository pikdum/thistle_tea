defmodule ThistleTea.Game.Entity.Logic.StealthCastingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.CastResolution.PowerCost
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "start/7" do
    test "rejects an unstealthed opener before side effects or costs", ctx do
      caster = %{ctx.caster | unit: %{ctx.caster.unit | auras: []}}
      assert CastValidation.validate(caster, ctx.sap, Target.unit(2), ctx.target, 0) == {:error, :only_stealthed}
      rejected = Casting.start(caster, ctx.sap, Target.unit(2), 0)
      assert rejected.internal.casting == nil
      assert rejected.internal.cooldowns == %{}
      assert rejected.unit.power4 == 100
      assert [%Effects.SpellCastFailed{reason: :only_stealthed}] = rejected.internal.events
    end

    test "an admitted ordinary opener consumes stealth before its cast time elapses", ctx do
      spell = %{ctx.sap | spell_icon: 244, family_flags_0: 0, cast_time_ms: 1_000}
      assert CastValidation.validate(ctx.caster, spell, Target.unit(2), ctx.target, 0) == :ok
      preparing = Casting.start(ctx.caster, spell, Target.unit(2), 0)
      refute Aura.has_aura?(preparing, :mod_stealth)
      assert preparing.internal.casting.phase == :preparing
      assert preparing.unit.power4 == 100
      completed = finish(preparing)
      assert completed.unit.power4 == 35
      assert completed.internal.in_combat
      refute Aura.has_aura?(completed, :mod_stealth)
    end

    test "a successful Sap roll survives launch while early and late invisibility still break", ctx do
      caster = add_talent(ctx.caster, 14_095)

      caster = %{
        caster
        | unit: %{
            caster.unit
            | auras: caster.unit.auras ++ [holder(2, :mod_invisibility, 4), holder(3, :mod_invisibility, 0x10000)]
          }
      }

      preparing = Casting.start(caster, ctx.sap, Target.unit(2), 0, nil, 0, stealth_roll: 90)
      assert preparing.internal.casting.preserve_stealth?
      assert Aura.has_aura?(preparing, :mod_stealth)
      refute Aura.has_spell?(preparing, 2)
      assert Aura.has_spell?(preparing, 3)
      completed = finish(preparing)
      assert Aura.has_aura?(completed, :mod_stealth)
      refute Aura.has_aura?(completed, :mod_invisibility)
      refute completed.internal.in_combat
      assert completed.unit.power4 == 35
    end

    test "a failed Sap roll and cancellation never recreate stealth", ctx do
      preparing = Casting.start(add_talent(ctx.caster, 14_095), ctx.sap, Target.unit(2), 0, nil, 0, stealth_roll: 91)
      refute Aura.has_aura?(preparing, :mod_stealth)
      cancelled = Casting.cancel(preparing, 0)
      refute Aura.has_aura?(cancelled, :mod_stealth)
      assert cancelled.unit.power4 == 100
      refute Aura.has_aura?(finish(preparing), :mod_stealth)
    end

    test "a successful roll does not restore stealth removed during preparation", ctx do
      preparing = Casting.start(add_talent(ctx.caster, 14_095), ctx.sap, Target.unit(2), 0, nil, 0, stealth_roll: 1)
      revealed = Aura.break_on_damage(preparing, 500)
      refute Aura.has_aura?(finish(revealed), :mod_stealth)
    end

    test "a resisted failure-breaks-stealth spell overrides preservation", ctx do
      spell = %{ctx.sap | attributes: MapSet.new([:allow_while_stealthed, :failure_breaks_stealth])}
      preparing = Casting.start(ctx.caster, spell, Target.unit(2), 0)
      completed = finish(preparing, :resist)
      refute Aura.has_aura?(completed, :mod_stealth)
      assert completed.internal.in_combat
    end

    test "peaceful-target requirements reject combat before consuming stealth", ctx do
      assert CastValidation.validate(ctx.caster, ctx.sap, Target.unit(2), %{ctx.target | unit_flags: 0x80000}, 0) ==
               {:error, :target_in_combat}

      assert CastValidation.validate_target(ctx.caster, ctx.sap, Target.unit(2), %{ctx.target | unit_flags: 0x80000}) ==
               :ok

      assert CastValidation.validate(ctx.caster, ctx.sap, Target.unit(2), %{ctx.target | unit_flags: 0x80000}, 0,
               triggered?: true
             ) == :ok
    end
  end

  describe "start_triggered/6" do
    test "triggered effects ignore the prerequisite and preserve action auras", ctx do
      spell = %{ctx.sap | effects: [], family_flags_0: 0}
      invisible = holder(3, :mod_invisibility, 0x10000)
      caster = %{ctx.caster | unit: %{ctx.caster.unit | auras: [invisible]}}
      completed = Casting.start_triggered(caster, spell, Target.self(1), 0, nil)
      assert completed.internal.casting == nil
      assert Aura.has_spell?(completed, 3)
      refute Enum.any?(completed.internal.events, &match?(%Effects.SpellCastFailed{}, &1))
    end
  end

  describe "complete/3" do
    test "a hostile triggered cast preserves stealth and late action auras", ctx do
      cast = %{Cast.new(ctx.sap, Target.unit(2), 0) | triggered?: true}

      caster = %{
        ctx.caster
        | internal: %{ctx.caster.internal | casting: cast},
          unit: %{ctx.caster.unit | auras: [holder(3, :mod_invisibility, 0x10000) | ctx.caster.unit.auras]}
      }

      completed = finish(caster)
      assert Aura.has_aura?(completed, :mod_stealth)
      assert Aura.has_aura?(completed, :mod_invisibility)
    end
  end

  defp finish(caster, outcome \\ :hit) do
    hits = if outcome == :hit, do: [2], else: []
    misses = if outcome == :hit, do: [], else: [%{guid: 2, reason: 2}]

    resolution = %CastResolution{
      hits: hits,
      misses: misses,
      impacts: [],
      costs: %Costs{
        power: %PowerCost{power_type: 3, amount: 65},
        channel_power: %PowerCost{power_type: nil, amount: 0},
        reagents: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      followups: %Followups{
        packet_hits: hits,
        selected_unit_guid: 2,
        object_guid: nil,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }

    cast = caster.internal.casting |> Cast.transition(:launch) |> Cast.put_resolution(resolution)
    Casting.complete(caster, cast, 1_000)
  end

  defp add_talent(caster, id),
    do: %{caster | unit: %{caster.unit | auras: [holder(id, :proc_trigger_spell, 0) | caster.unit.auras]}}

  defp holder(id, type, flags),
    do: %Holder{spell: %Spell{id: id, aura_interrupt_flags: flags}, caster_guid: 1, auras: [%AuraData{type: type}]}

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 60,
        power_type: 3,
        power4: 100,
        max_power4: 100,
        auras: [holder(1784, :mod_stealth, 0x3C07)]
      },
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    sap = %Spell{
      id: 6770,
      spell_icon: 249,
      spell_family: 8,
      family_flags_0: 0x80,
      power_type: 3,
      mana_cost: 65,
      attributes: MapSet.new([:only_stealthed, :only_peaceful_targets]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}]
    }

    %{caster: caster, sap: sap, target: %{alive?: true, friendly?: false, hostile?: true, unit_flags: 0}}
  end
end
