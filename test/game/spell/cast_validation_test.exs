defmodule ThistleTea.Game.Spell.CastValidationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.WorldRef

  @now 10_000

  defp caster(unit_overrides \\ []) do
    unit =
      struct!(
        %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
        unit_overrides
      )

    %Mob{
      object: %Object{guid: 100},
      unit: unit,
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end

  defp harmful_spell(overrides \\ []) do
    struct!(
      %Spell{
        id: 133,
        mana_cost: 30,
        power_type: 0,
        range_yards: 35.0,
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]
      },
      overrides
    )
  end

  defp helpful_spell(overrides \\ []) do
    struct!(
      %Spell{
        id: 1454,
        mana_cost: 0,
        range_yards: 40.0,
        effects: [%Effect{type: :heal, implicit_target_a: :target_ally}]
      },
      overrides
    )
  end

  defp hostile_target(overrides \\ []) do
    Map.merge(
      %{
        guid: 7,
        alive?: true,
        hostile?: true,
        friendly?: false,
        attackable?: true,
        position: {WorldRef.open(0), 10.0, 0.0, 0.0}
      },
      Map.new(overrides)
    )
  end

  defp friendly_target(overrides \\ []) do
    hostile_target([hostile?: false, friendly?: true, attackable?: false] ++ overrides)
  end

  describe "stance gating" do
    test "stance-locked abilities fail outside their form, including no form at all" do
      claw = harmful_spell(id: 1082, stances: 0x1)

      assert {:error, :only_shapeshift} =
               CastValidation.validate(caster(), claw, Targets.unit(7), hostile_target(), @now)

      assert {:error, :only_shapeshift} =
               CastValidation.validate(caster(shapeshift_form: 5), claw, Targets.unit(7), hostile_target(), @now)

      assert :ok = CastValidation.validate(caster(shapeshift_form: 1), claw, Targets.unit(7), hostile_target(), @now)
    end

    test "normal spells fail in true forms but cast fine in warrior-style stances" do
      fireball = harmful_spell(attributes: MapSet.new([:not_while_shapeshifted]))

      assert {:error, :not_shapeshift} =
               CastValidation.validate(caster(shapeshift_form: 1), fireball, Targets.unit(7), hostile_target(), @now)

      assert :ok =
               CastValidation.validate(caster(shapeshift_form: 17), fireball, Targets.unit(7), hostile_target(), @now)

      assert :ok = CastValidation.validate(caster(), fireball, Targets.unit(7), hostile_target(), @now)
    end

    test "stance-excluded spells fail in the excluded form" do
      renew = helpful_spell(stances_not: 0x08000000)

      assert {:error, :not_shapeshift} =
               CastValidation.validate(caster(shapeshift_form: 28), renew, %Targets{}, nil, @now)

      assert :ok = CastValidation.validate(caster(), renew, %Targets{}, nil, @now)
    end
  end

  describe "validate/6" do
    test "passes a valid hostile cast" do
      assert :ok =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), hostile_target(), @now)
    end

    test "uses current health for health-powered spells" do
      spell = helpful_spell(mana_cost: 30, power_type: -2)

      assert :ok = CastValidation.validate(caster(health: 31), spell, %Targets{}, nil, @now)
      assert {:error, :no_power} = CastValidation.validate(caster(health: 30), spell, %Targets{}, nil, @now)
    end

    test "restricts Exorcism and Holy Wrath to undead or demons" do
      exorcism = harmful_spell(name: "Exorcism", target_creature_type_mask: 36)
      holy_wrath = harmful_spell(name: "Holy Wrath", target_creature_type_mask: 36)

      assert :ok =
               CastValidation.validate(caster(), exorcism, Targets.unit(7), hostile_target(creature_type: 6), @now)

      assert :ok =
               CastValidation.validate(caster(), holy_wrath, Targets.unit(7), hostile_target(creature_type: 3), @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), exorcism, Targets.unit(7), hostile_target(creature_type: 7), @now)

      holy_wrath = %{
        holy_wrath
        | effects: [%Effect{type: :school_damage, implicit_target_a: :aoe_enemy_at_caster}]
      }

      assert :ok = CastValidation.validate(caster(), holy_wrath, %Targets{}, nil, @now)
    end

    test "restricts Turn Undead to undead targets" do
      turn_undead = %{
        harmful_spell(name: "Turn Undead", target_creature_type_mask: 32)
        | effects: [%Effect{type: :apply_aura, aura: :mod_fear, implicit_target_a: :target_enemy}]
      }

      assert :ok =
               CastValidation.validate(caster(), turn_undead, Targets.unit(7), hostile_target(creature_type: 6), @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), turn_undead, Targets.unit(7), hostile_target(creature_type: 3), @now)
    end

    test "rejects a dead caster" do
      assert {:error, :caster_dead} =
               CastValidation.validate(caster(health: 0), harmful_spell(), Targets.unit(7), hostile_target(), @now)
    end

    test "rejects insufficient power" do
      assert {:error, :no_power} =
               CastValidation.validate(caster(power1: 10), harmful_spell(), Targets.unit(7), hostile_target(), @now)
    end

    test "rejects a spell still on cooldown and allows it after expiry" do
      spell = harmful_spell(recovery_time_ms: 8_000)
      caster = Cooldowns.start(caster(), spell, @now)

      assert {:error, :not_ready} =
               CastValidation.validate(caster, spell, Targets.unit(7), hostile_target(), @now + 7_999)

      assert :ok =
               CastValidation.validate(caster, spell, Targets.unit(7), hostile_target(), @now + 8_000)
    end

    test "rejects missing reagents and passes when they are on hand" do
      spell = helpful_spell(reagents: [{17_056, 1}])

      assert {:error, :reagents} =
               CastValidation.validate(caster(), spell, Targets.unit(100), :self, @now, count_item: fn _ -> 0 end)

      assert :ok =
               CastValidation.validate(caster(), spell, Targets.unit(100), :self, @now, count_item: fn _ -> 2 end)
    end

    test "rejects a friendly target for a harmful spell" do
      assert {:error, :target_friendly} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), friendly_target(), @now)
    end

    test "rejects a dead target for a harmful spell" do
      assert {:error, :targets_dead} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), hostile_target(alive?: false), @now)
    end

    test "rejects an unattackable neutral target for a harmful spell" do
      target = hostile_target(hostile?: false, attackable?: false)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), target, @now)
    end

    test "rejects a hostile target for a helpful spell" do
      assert {:error, :target_enemy} =
               CastValidation.validate(caster(), helpful_spell(), Targets.unit(7), hostile_target(), @now)
    end

    test "allows a self-targeting spell cast with an enemy selected" do
      arcane_missiles = %Spell{
        id: 5143,
        mana_cost: 50,
        power_type: 0,
        range_yards: 30.0,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{type: :apply_aura, aura: :periodic_trigger_spell, implicit_target_a: :caster}]
      }

      assert :ok =
               CastValidation.validate(caster(), arcane_missiles, Targets.unit(7), hostile_target(), @now)

      assert {:error, :targets_dead} =
               CastValidation.validate(
                 caster(),
                 arcane_missiles,
                 Targets.unit(7),
                 hostile_target(alive?: false),
                 @now
               )
    end

    test "requires a unit target for harmful spells" do
      assert {:error, :bad_implicit_targets} =
               CastValidation.validate(caster(), harmful_spell(), %Targets{raw: <<>>}, nil, @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(100), :self, @now)

      assert {:error, :bad_targets} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), :unknown, @now)
    end

    test "rejects targets out of line of sight" do
      assert {:error, :line_of_sight} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), hostile_target(los?: false), @now)
    end

    test "requires a matching removable aura for non-periodic dispels" do
      cleanse =
        helpful_spell(
          name: "Cleanse",
          effects: [
            %Effect{type: :dispel, misc_value: 4, implicit_target_a: :target_ally},
            %Effect{type: :dispel, misc_value: 3, implicit_target_a: :target_ally},
            %Effect{type: :dispel, misc_value: 1, implicit_target_a: :target_ally}
          ]
        )

      assert {:error, :nothing_to_dispel} =
               CastValidation.validate(caster(), cleanse, Targets.unit(7), friendly_target(), @now)

      assert :ok =
               CastValidation.validate(
                 caster(),
                 cleanse,
                 Targets.unit(7),
                 friendly_target(dispel_options: MapSet.new([{3, :negative}])),
                 @now
               )

      assert {:error, :nothing_to_dispel} =
               CastValidation.validate(
                 caster(),
                 cleanse,
                 Targets.unit(7),
                 friendly_target(dispel_options: MapSet.new([{3, :positive}])),
                 @now
               )
    end

    test "offensive dispels require a matching positive aura" do
      purge = harmful_spell(effects: [%Effect{type: :dispel, misc_value: 1, implicit_target_a: :target_enemy}])
      target = hostile_target(dispel_options: MapSet.new([{1, :positive}]))

      assert :ok = CastValidation.validate(caster(), purge, Targets.unit(7), target, @now)
    end

    test "rejects power burn against a different target resource" do
      mana_burn =
        harmful_spell(effects: [%Effect{type: :power_burn, misc_value: 0, implicit_target_a: :target_enemy}])

      assert :ok =
               CastValidation.validate(
                 caster(),
                 mana_burn,
                 Targets.unit(7),
                 hostile_target(power_type: 0),
                 @now
               )

      assert {:error, :bad_targets} =
               CastValidation.validate(
                 caster(),
                 mana_burn,
                 Targets.unit(7),
                 hostile_target(power_type: 1),
                 @now
               )
    end

    test "allows ignore_line_of_sight spells to bypass the LoS check" do
      spell = harmful_spell(attributes: MapSet.new([:ignore_line_of_sight]))

      assert :ok = CastValidation.validate(caster(), spell, Targets.unit(7), hostile_target(los?: false), @now)
    end

    test "skips the LoS check when target info has no visibility fact" do
      assert :ok = CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), hostile_target(), @now)
    end

    test "rejects targets out of range or on another map" do
      out_of_range = hostile_target(position: {WorldRef.open(0), 100.0, 0.0, 0.0})
      other_map = hostile_target(position: {WorldRef.open(1), 10.0, 0.0, 0.0})

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), out_of_range, @now)

      assert {:error, :out_of_range} =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), other_map, @now)
    end

    test "skips the range check when the target position is unknown" do
      assert :ok =
               CastValidation.validate(
                 caster(),
                 harmful_spell(),
                 Targets.unit(7),
                 hostile_target(position: nil),
                 @now
               )
    end
  end
end
