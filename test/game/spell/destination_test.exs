defmodule ThistleTea.Game.Spell.DestinationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Destination
  alias ThistleTea.Game.Spell.Target

  setup [:build_casters]

  describe "validate/4" do
    test "checks three-dimensional distance with bounding radius and player casting leeway", ctx do
      assert Destination.validate(ctx.player, ctx.spell, Target.at({0.0, 0.0, 31.75}), true) == :ok
      assert Destination.validate(ctx.player, ctx.spell, Target.at({0.0, 0.0, 31.76}), true) == {:error, :out_of_range}
      assert Destination.validate(ctx.pet, ctx.spell, Target.at({0.0, 0.0, 30.5}), true) == :ok
      assert Destination.validate(ctx.pet, ctx.spell, Target.at({0.0, 0.0, 30.51}), true) == {:error, :out_of_range}
    end

    test "rejects too-close locations and blocked sight while honoring the spell exception", ctx do
      spell = %{ctx.spell | min_range_yards: 8.0}
      assert Destination.validate(ctx.pet, spell, Target.at({8.0, 0.0, 0.0}), true) == {:error, :too_close}
      assert Destination.validate(ctx.pet, spell, Target.at({20.0, 0.0, 0.0}), false) == {:error, :line_of_sight}
      spell = %{spell | attributes: MapSet.new([:ignore_line_of_sight])}
      assert Destination.validate(ctx.pet, spell, Target.at({20.0, 0.0, 0.0}), false) == :ok
    end

    test "applies range talents without treating combat reach as destination reach", ctx do
      holder = %Holder{
        spell: %Spell{id: 2, spell_family: 3},
        auras: [%Aura{type: :add_pct_modifier, misc_value: 5, amount: 20, class_mask: 1}]
      }

      player = %{ctx.player | unit: %{ctx.player.unit | auras: [holder], combat_reach: 100.0}}
      assert Destination.validate(player, ctx.spell, Target.at({37.75, 0.0, 0.0}), true) == :ok
      assert Destination.validate(player, ctx.spell, Target.at({37.76, 0.0, 0.0}), true) == {:error, :out_of_range}
    end

    test "leaves a unit selection's accompanying destination to its unit validation", ctx do
      targets = %{Target.unit(20) | destination_location: {200.0, 0.0, 0.0}}
      assert Destination.validate(ctx.player, ctx.spell, targets, false) == :ok
    end
  end

  describe "CastValidation.validate/6" do
    test "admits reachable ground casts and rejects invalid destinations before execution", ctx do
      assert CastValidation.validate(ctx.pet, ctx.spell, Target.at({20.0, 0.0, 0.0}), nil, 0) == :ok

      assert CastValidation.validate(ctx.pet, ctx.spell, Target.at({60.0, 0.0, 0.0}), nil, 0) ==
               {:error, :out_of_range}

      assert CastValidation.validate(ctx.pet, ctx.spell, Target.at({20.0, 0.0, 0.0}), nil, 0, destination_los?: false) ==
               {:error, :line_of_sight}
    end
  end

  defp build_casters(_context) do
    unit = %Unit{health: 100, power1: 100, bounding_radius: 0.5}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    player = %Character{unit: unit, movement_block: movement, internal: %Internal{}}
    pet = %Mob{unit: unit, movement_block: movement, internal: %Internal{}}
    spell = %Spell{id: 1, range_yards: 30.0, spell_family: 3, family_flags_0: 1}
    %{player: player, pet: pet, spell: spell}
  end
end
