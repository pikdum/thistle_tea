defmodule ThistleTea.Game.Core.Spell.RangeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Mob.Spells
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Range
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef

  setup [:build_caster]

  describe "maximum/2" do
    test "preserves spells without a positive base range", ctx do
      for range <- [nil, 0.0] do
        spell = %{ctx.spell | range_yards: range}
        assert Range.maximum(ctx.caster, spell) == range
        assert Range.channel_maximum(ctx.caster, spell, true) == range
      end
    end
  end

  describe "validate_target/4" do
    test "applies flat and percent range before cast leeway and preserves the base spell", ctx do
      assert validate(ctx.caster, ctx.spell, 52.5) == :ok
      assert validate(ctx.caster, ctx.spell, 52.6) == {:error, :out_of_range}
      assert ctx.spell.range_yards == 30.0

      reset = %{ctx.caster | unit: %{ctx.caster.unit | auras: []}}
      assert validate(reset, ctx.spell, 30.0) == :ok
      assert validate(reset, ctx.spell, 30.1) == {:error, :out_of_range}
    end

    test "excludes unrelated families and masks", ctx do
      for spell <- [%{ctx.spell | spell_family: 8}, %{ctx.spell | family_flags_0: 2}] do
        assert validate(ctx.caster, spell, 36.0) == {:error, :out_of_range}
      end
    end

    test "retains minimum range, combat reach, and world isolation", ctx do
      spell = %{ctx.spell | min_range_yards: 8.0}
      caster = %{ctx.caster | unit: %{ctx.caster.unit | combat_reach: 1.5}}
      assert validate(caster, spell, 9.4) == {:error, :too_close}
      assert validate(caster, spell, 9.5) == :ok
      assert validate(caster, spell, 54.0) == :ok

      target = target(20.0) |> Map.put(:position, {WorldRef.open(1), 20.0, 0.0, 0.0})
      assert CastValidation.validate_target(caster, spell, Target.unit(2), target) == {:error, :out_of_range}
    end

    test "does not turn a reduced range into unlimited range", ctx do
      aura = %Aura{type: :add_flat_modifier, misc_value: 5, amount: -100, class_mask: 1}
      holder = %{ctx.holder | auras: [aura]}
      caster = %{ctx.caster | unit: %{ctx.caster.unit | auras: [holder]}}
      assert validate(caster, ctx.spell, 0.0) == :ok
      assert validate(caster, ctx.spell, 0.1) == {:error, :out_of_range}
    end
  end

  describe "validate/4" do
    test "distinguishes player and creature admission and launch allowances", ctx do
      player = struct!(Character, Map.from_struct(ctx.caster) |> Map.take([:object, :unit, :internal, :movement_block]))

      for {caster, phase, allowance} <- [
            {ctx.caster, :start, 0.0},
            {ctx.caster, :launch, 2.25},
            {player, :start, 1.25},
            {player, :launch, 6.25}
          ] do
        limit = 52.5 + allowance
        assert Range.validate(caster, ctx.spell, target(limit), phase: phase) == :ok
        assert Range.validate(caster, ctx.spell, target(limit + 0.01), phase: phase) == {:error, :out_of_range}
      end
    end

    test "requires both units to move quickly and at least one player for movement allowance", ctx do
      movement = %{ctx.caster.movement_block | movement_flags: 1, run_speed: 7.0}
      caster = %{ctx.caster | movement_block: movement}
      moving = Map.put(target(55.16), :lateral_speed, 7.0)
      assert Range.validate(caster, ctx.spell, moving) == :ok
      assert Range.validate(caster, ctx.spell, %{moving | lateral_speed: 4.97}) == {:error, :out_of_range}
      assert Range.validate(ctx.caster, ctx.spell, moving) == {:error, :out_of_range}
      creature = %{moving | guid: Guid.runtime(:mob, 2)}
      assert Range.validate(caster, ctx.spell, creature) == {:error, :out_of_range}
    end

    test "melee spells use horizontal reach with a minimum size and no extra launch allowance", ctx do
      caster = %{ctx.caster | unit: %{ctx.caster.unit | auras: [], combat_reach: 0.5}}
      spell = %{ctx.spell | melee_range?: true, range_yards: 5.0}
      inside = %{target(5.332) | position: {caster.internal.world, 5.332, 0.0, 100.0}}

      for phase <- [:start, :launch] do
        assert Range.validate(caster, spell, inside, phase: phase) == :ok
        assert Range.validate(caster, spell, target(5.333), phase: phase) == {:error, :out_of_range}
      end

      assert Range.validate(ctx.caster, spell, target(15.332)) == :ok
      assert Range.validate(ctx.caster, spell, target(15.334)) == {:error, :out_of_range}
    end

    test "triggered spells bypass range and minimum range checks", ctx do
      spell = %{ctx.spell | min_range_yards: 8.0}
      assert Range.validate(ctx.caster, spell, target(1_000.0), triggered?: true) == :ok
      assert Range.validate(ctx.caster, spell, target(0.0), triggered?: true) == :ok
    end
  end

  describe "channel_in_range?/3" do
    test "applies range modifiers after hostile and friendly channel grace", ctx do
      for {hostile?, distance} <- [{true, 67.35}, {false, 54.375}] do
        inside = Map.put(target(distance), :hostile?, hostile?)
        outside = Map.put(target(distance + 0.01), :hostile?, hostile?)
        assert CastValidation.channel_in_range?(ctx.caster, ctx.spell, inside)
        refute CastValidation.channel_in_range?(ctx.caster, ctx.spell, outside)

        reset = %{ctx.caster | unit: %{ctx.caster.unit | auras: []}}
        refute CastValidation.channel_in_range?(reset, ctx.spell, inside)
      end
    end
  end

  describe "observation_radius/1" do
    test "pet target discovery includes inherited range bonuses", ctx do
      pet = %{
        ctx.caster
        | unit: %{ctx.caster.unit | auras: []},
          internal: %{
            ctx.caster.internal
            | pet: %Pet{owner_guid: 10, owner_spell_modifiers: [ctx.holder]},
              spellbook: %{ctx.spell.id => ctx.spell}
          }
      }

      assert Spells.observation_radius(pet) == 52.5
      assert validate(pet, ctx.spell, 50.0) == :ok
    end
  end

  defp validate(caster, spell, distance),
    do: CastValidation.validate_target(caster, spell, Target.unit(2), target(distance))

  defp target(distance) do
    %{guid: 2, alive?: true, hostile?: true, position: {WorldRef.open(0), distance, 0.0, 0.0}}
  end

  defp build_caster(_context) do
    holder = %Holder{
      spell: %Spell{id: 900, spell_family: 3},
      auras: [
        %Aura{type: :add_flat_modifier, misc_value: 5, amount: 5, class_mask: 1},
        %Aura{type: :add_pct_modifier, misc_value: 5, amount: 50, class_mask: 1}
      ]
    }

    caster = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, auras: [holder]},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 100,
      range_yards: 30.0,
      spell_family: 3,
      family_flags_0: 1,
      effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
    }

    %{caster: caster, holder: holder, spell: spell}
  end
end
