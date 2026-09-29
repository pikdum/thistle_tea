defmodule ThistleTea.Game.Core.Spell.CastingResourcesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef

  setup [:caster]

  describe "complete/2" do
    test "ordinary creatures launch admitted abilities without the corresponding resource pool", ctx do
      for type <- 0..4, pet <- [nil, %Pet{kind: :charmed, owner_guid: 2}] do
        spell = %{ctx.spell | power_type: type}
        caster = %{ctx.caster | internal: %{ctx.caster.internal | pet: pet}}
        assert CastValidation.validate(caster, spell, ctx.target, :self, 1_000) == :ok
        completed = caster |> Casting.start(spell, ctx.target, 1_000) |> Casting.complete(2_000)
        assert completed.internal.casting == nil
        assert completed.unit.health > 50
        assert completed.unit.power1 == 0
        assert completed.unit.power2 == nil
        assert completed.unit.power4 == nil
        assert Enum.any?(completed.internal.events, &is_struct(&1, Effects.SpellGo))
        refute Enum.any?(completed.internal.events, &is_struct(&1, Effects.SpellCastFailed))
      end
    end

    test "pets and players cannot launch without the required resource", ctx do
      player = %Character{
        object: ctx.caster.object,
        unit: ctx.caster.unit,
        internal: ctx.caster.internal,
        movement_block: ctx.caster.movement_block,
        player: %Player{}
      }

      pet = %{ctx.caster | internal: %{ctx.caster.internal | pet: %Pet{kind: :hunter, owner_guid: 2}}}

      for caster <- [pet, player], type <- 0..4 do
        spell = %{ctx.spell | power_type: type}
        assert CastValidation.validate(caster, spell, ctx.target, :self, 1_000) == {:error, :no_power}
        failed = caster |> Casting.start(spell, ctx.target, 1_000) |> Casting.complete(2_000)
        assert_failed(failed, :no_power)
      end
    end

    test "a mana creature that loses power during preparation cannot launch", ctx do
      caster = %{ctx.caster | unit: %{ctx.caster.unit | base_mana: 100, max_power1: 100, power1: 100}}
      spell = %{ctx.spell | mana_cost: 60}
      started = Casting.start(caster, spell, ctx.target, 1_000)
      drained = %{started | unit: %{started.unit | power1: 59}}
      failed = Casting.complete(drained, 2_000)
      assert_failed(failed, :no_power)
      assert failed.unit.power1 == 59

      completed = Casting.complete(started, 2_000)
      assert completed.unit.power1 == 40
      assert completed.unit.health > 50
      assert completed.internal.last_mana_use_at == 2_000
      assert Casting.complete(completed, 2_100).unit.power1 == 40
    end

    test "launch recalculates the scaled cost when a cost aura arrives during preparation", ctx do
      caster = %{ctx.caster | unit: %{ctx.caster.unit | base_mana: 500, max_power1: 500, power1: 500}}
      spell = %{ctx.spell | mana_cost: 90, spell_level: 20, attributes: MapSet.new([:scales_with_creature_level])}
      started = Casting.start(caster, spell, ctx.target, 1_000)
      holder = %Holder{spell: %Spell{id: 2}, auras: [%Aura{type: :mod_power_cost_school, misc_value: 4, amount: -30}]}
      discounted = %{started | unit: %{started.unit | auras: [holder]}}
      assert Casting.complete(started, 2_000).unit.power1 == 214
      assert Casting.complete(discounted, 2_000).unit.power1 == 309
    end

    test "item casts bypass power admission and payment without starting the mana-use timer", ctx do
      caster = %{ctx.caster | unit: %{ctx.caster.unit | base_mana: 100, max_power1: 100}}
      assert CastValidation.validate(caster, ctx.spell, ctx.target, :self, 1_000) == {:error, :no_power}
      assert CastValidation.validate(caster, ctx.spell, ctx.target, :self, 1_000, cast_item_guid: 42) == :ok
      completed = caster |> Casting.start(ctx.spell, ctx.target, 1_000, 42) |> Casting.complete(2_000)
      assert completed.unit.health > 50
      assert completed.unit.power1 == 0
      assert completed.internal.last_mana_use_at == nil
      assert Enum.any?(completed.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "health-cost failures retain health and report the caster aura state", ctx do
      spell = %{ctx.spell | power_type: -2, mana_cost: 50}
      failed = ctx.caster |> Casting.start(spell, ctx.target, 1_000) |> Casting.complete(2_000)
      assert_failed(failed, :caster_aurastate)
    end
  end

  defp assert_failed(entity, reason) do
    assert entity.unit.health == 50
    assert entity.internal.casting == nil
    assert entity.internal.cooldowns == %{}
    refute Enum.any?(entity.internal.events, &is_struct(&1, Effects.SpellGo))
    assert Enum.any?(entity.internal.events, &match?(%Effects.SpellCastFailed{reason: ^reason}, &1))
  end

  defp caster(_context) do
    %{
      caster: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 50, max_health: 100, level: 50, power1: 0, max_power1: 0, base_mana: 0, auras: []},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      },
      spell: %Spell{
        id: 900_851,
        mana_cost: 30,
        power_type: 0,
        school: :fire,
        cast_time_ms: 1_000,
        recovery_time_ms: 5_000,
        effects: [%Effect{index: 0, type: :heal, implicit_target_a: :caster, base_points: 9}]
      },
      target: Target.self(1)
    }
  end
end
