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
      internal: %Internal{map: 0}
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
        position: {0, 10.0, 0.0, 0.0}
      },
      Map.new(overrides)
    )
  end

  defp friendly_target(overrides \\ []) do
    hostile_target([hostile?: false, friendly?: true, attackable?: false] ++ overrides)
  end

  describe "validate/6" do
    test "passes a valid hostile cast" do
      assert :ok =
               CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), hostile_target(), @now)
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

    test "allows ignore_line_of_sight spells to bypass the LoS check" do
      spell = harmful_spell(attributes: MapSet.new([:ignore_line_of_sight]))

      assert :ok = CastValidation.validate(caster(), spell, Targets.unit(7), hostile_target(los?: false), @now)
    end

    test "skips the LoS check when target info has no visibility fact" do
      assert :ok = CastValidation.validate(caster(), harmful_spell(), Targets.unit(7), hostile_target(), @now)
    end

    test "rejects targets out of range or on another map" do
      out_of_range = hostile_target(position: {0, 100.0, 0.0, 0.0})
      other_map = hostile_target(position: {1, 10.0, 0.0, 0.0})

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
