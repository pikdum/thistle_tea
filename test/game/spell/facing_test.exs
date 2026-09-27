defmodule ThistleTea.Game.Spell.FacingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastTarget
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Facing
  alias ThistleTea.Game.Spell.Requirements
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "validate/4" do
    test "checks the forward semicircle with wrapped angles", %{caster: caster, spell: spell, target: target} do
      for offset <- [-4, -2, 0, 2, 4], angle <- [-:math.pi() / 2, 0, :math.pi() / 2] do
        assert Facing.validate(turn(caster, angle + offset * :math.pi()), spell, target) == :ok
      end

      for angle <- [-:math.pi() / 2 - 0.001, :math.pi() / 2 + 0.001, :math.pi()] do
        assert Facing.validate(turn(caster, angle), spell, target) == {:error, :unit_not_infront}
      end
    end

    test "uses planar overlap below 1.4 yards", %{caster: caster, spell: spell, target: target} do
      near = %{target | position: {caster.internal.world, -1.399, 0.0, 10.0}}
      edge = %{target | position: {caster.internal.world, -1.4, 0.0, 0.0}}
      assert Facing.validate(caster, spell, near) == :ok
      assert Facing.validate(caster, spell, edge) == {:error, :unit_not_infront}
    end

    test "preserves unrestricted, self, triggered and queued casts", %{caster: caster, spell: spell, target: target} do
      caster = turn(caster, :math.pi())
      assert Facing.validate(caster, %{spell | custom_flags: 0}, target) == :ok
      assert Facing.validate(caster, spell, :self) == :ok
      assert Facing.validate(caster, spell, target, triggered?: true) == :ok
      assert CastValidation.validate_target(caster, spell, Target.unit(2), target, triggered?: true) == :ok

      queued = %{spell | melee_range?: true, attributes: MapSet.new([:on_next_swing])}
      assert Facing.validate(caster, queued, target) == :ok
      refute Facing.required?(caster, queued)
      refute Requirements.required?(caster, spell, triggered?: true)
    end

    test "enforces combat-range spells for creatures but leaves ranged creature turning to AI", data do
      caster = turn(data.caster, :math.pi())
      mob = %Mob{movement_block: caster.movement_block}
      melee = %{data.spell | custom_flags: 0, melee_range?: true}
      assert Facing.validate(caster, melee, data.target) == {:error, :unit_not_infront}
      assert Facing.validate(mob, melee, data.target) == {:error, :unit_not_infront}
      assert Facing.validate(mob, data.spell, data.target) == :ok
      assert Facing.validate(mob, melee, data.target, triggered?: true) == :ok
    end

    test "keeps the caster and target facing requirements distinct", %{caster: caster, spell: spell, target: target} do
      gouge = %{spell | attributes: MapSet.new([:target_facing_caster])}
      backstab = %{spell | attributes: MapSet.new([:from_behind])}
      assert Facing.validate(caster, gouge, target) == {:error, :not_infront}
      assert Facing.validate(caster, backstab, target) == :ok
      assert Facing.validate(turn(caster, :math.pi()), backstab, target) == {:error, :unit_not_infront}

      facing = %{target | orientation: :math.pi()}
      assert Facing.validate(caster, gouge, facing) == :ok
      assert Facing.validate(caster, backstab, facing) == {:error, :not_behind}
    end

    test "uses the facing rule for auto-repeat initiation", %{caster: caster, target: target} do
      shot = %Spell{attributes: MapSet.new([:uses_ranged_slot, :auto_repeat])}
      assert Facing.validate(turn(caster, :math.pi()), shot, target) == {:error, :unit_not_infront}
    end
  end

  describe "validate_target/5" do
    test "rejects a backwards caster and reuses the same requirement at launch", data do
      caster = turn(data.caster, :math.pi())

      assert CastValidation.validate_target(caster, data.spell, Target.unit(2), data.target) ==
               {:error, :unit_not_infront}

      assert Requirements.required?(caster, data.spell)

      context = %CastTarget{targets: Target.unit(2), info: data.target}

      assert Requirements.validate(caster, data.spell, %Requirements{cast_target: context}) ==
               {:error, :unit_not_infront}
    end
  end

  defp caster(_context) do
    world = WorldRef.open(0)

    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      },
      spell: %Spell{
        id: 133,
        custom_flags: 0x80,
        range_yards: 30.0,
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
      },
      target: %{guid: 2, alive?: true, hostile?: true, position: {world, 5.0, 0.0, 0.0}, orientation: 0.0}
    }
  end

  defp turn(caster, angle), do: %{caster | movement_block: %{caster.movement_block | position: {0.0, 0.0, 0.0, angle}}}
end
