defmodule ThistleTea.Game.Spell.CostScalingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CostScaling

  setup [:caster]

  describe "base_cost/2" do
    test "uses creature level in five-point steps and caps the spell rank", ctx do
      assert CostScaling.base_cost(ctx.mob, ctx.spell) == 125
      assert CostScaling.base_cost(%{ctx.mob | unit: %{ctx.mob.unit | level: 54}}, ctx.spell) == 125
      assert CostScaling.base_cost(%{ctx.mob | unit: %{ctx.mob.unit | level: 55}}, ctx.spell) == 130
      assert CostScaling.base_cost(ctx.mob, %{ctx.spell | max_level: 8}) == 115
    end

    test "uses the player's spell skill and bonuses rather than character level", ctx do
      spell = %{ctx.spell | cost_skill_id: 8}
      assert CostScaling.base_cost(ctx.player, spell) == 320
      assert CostScaling.base_cost(ctx.player, %{spell | max_level: 20}) == 175
      bonus = %Holder{spell: %Spell{id: 1}, auras: [%Aura{type: :mod_skill, misc_value: 8, amount: 5}]}
      player = %{ctx.player | unit: %{ctx.player.unit | auras: [bonus]}}
      assert CostScaling.base_cost(player, spell) == 325
      assert CostScaling.base_cost(player, %{spell | cost_skill_id: 9}) == 75
      assert CostScaling.base_cost(player, %{spell | cost_skill_id: nil}) == 75
    end
  end

  describe "power_cost/3" do
    test "orders base, school flat, family, creature scaling and school percentage modifiers", ctx do
      holder = %Holder{
        spell: %Spell{id: 1, spell_family: 3},
        auras: [
          %Aura{type: :mod_power_cost_school, misc_value: 4, amount: 10},
          %Aura{type: :add_flat_modifier, misc_value: 14, class_mask: 1, amount: -5},
          %Aura{type: :add_pct_modifier, misc_value: 14, class_mask: 1, amount: -20},
          %Aura{type: :mod_power_cost_school_pct, misc_value: 4, amount: 10}
        ]
      }

      caster = %{ctx.mob | unit: %{ctx.mob.unit | auras: [holder], base_mana: 1_000}}

      spell = %{
        ctx.spell
        | mana_cost_percent: 5,
          spell_family: 3,
          family_flags_0: 1,
          spell_level: 20,
          attributes: MapSet.new([:scales_with_creature_level])
      }

      assert Resources.power_cost(caster, spell) == 503
      assert spell.mana_cost == 100
      assert Resources.power_cost(caster, %{spell | attributes: MapSet.new()}) == 158
      assert Resources.power_cost(ctx.mob, spell) == 557
    end

    test "truncates fractional family costs and clamps after level scaling", ctx do
      holder = %Holder{
        spell: %Spell{id: 1, spell_family: 3},
        auras: [%Aura{type: :add_pct_modifier, misc_value: 14, class_mask: 1, amount: -10}]
      }

      spell = %{ctx.spell | mana_cost: 3, mana_cost_per_level: 0, spell_family: 3, family_flags_0: 1}
      caster = %{ctx.mob | unit: %{ctx.mob.unit | auras: [holder]}}
      assert Resources.power_cost(caster, spell) == 2

      spell = %{spell | spell_level: 5, attributes: MapSet.new([:scales_with_creature_level])}
      assert Resources.power_cost(caster, spell) == 0
      assert Resources.power_cost(caster, %{spell | spell_level: 0}) == 2
    end

    test "item and triggered casts are free before all-power or level modifiers", ctx do
      spell = %{ctx.spell | attributes: MapSet.new([:use_all_mana, :scales_with_creature_level])}
      assert Resources.power_cost(ctx.player, spell) == 500
      assert Resources.power_cost(ctx.player, spell, cast_item_guid: 42) == 0
      assert Resources.power_cost(ctx.player, spell, triggered?: true) == 0
    end
  end

  defp caster(_context) do
    unit = %Unit{health: 100, level: 50, power1: 500, max_power1: 1_000, auras: []}

    %{
      mob: %Mob{unit: unit, internal: %Internal{}},
      player: %Character{unit: unit, player: %Player{skills: %{8 => %{value: 249}}}, internal: %Internal{}},
      spell: %Spell{mana_cost: 100, mana_cost_per_level: 5, power_type: 0, school: :fire, base_level: 5}
    }
  end
end
