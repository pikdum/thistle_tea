defmodule ThistleTea.Game.Spell.DuelCastValidationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Duel.Admission
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  describe "validate/6 duel checks" do
    test "accepts two available players in duel-enabled areas" do
      assert :ok = validate(duel_context())
    end

    test "rejects occupied targets and disabled areas" do
      assert {:error, :target_dueling} = validate(%{duel_context() | opponent_busy?: true})
      assert {:error, :no_dueling} = validate(%{duel_context() | initiator_allowed?: false})
    end

    test "rejects non-player and cross-world targets" do
      assert {:error, :bad_targets} = validate(%{duel_context() | opponent_player?: false})
      assert {:error, :bad_targets} = validate(%{duel_context() | same_world?: false})
    end
  end

  defp validate(context) do
    CastValidation.validate(
      caster(),
      duel_spell(),
      Target.unit(2),
      target_info(),
      1_000,
      duel_context: context
    )
  end

  defp duel_context do
    %Admission{
      initiator_guid: 1,
      opponent_guid: 2,
      initiator_player?: true,
      opponent_player?: true,
      initiator_online?: true,
      opponent_online?: true,
      initiator_busy?: false,
      opponent_busy?: false,
      initiator_allowed?: true,
      opponent_allowed?: true,
      same_world?: true
    }
  end

  defp caster do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 20, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp duel_spell do
    %Spell{
      id: 7_266,
      mana_cost: 0,
      power_type: 0,
      range_yards: 30.0,
      effects: [%Effect{type: :duel, misc_value: 21_680, implicit_target_a: :any_unit}]
    }
  end

  defp target_info do
    %{
      guid: 2,
      alive?: true,
      hostile?: false,
      friendly?: true,
      position: {WorldRef.open(0), 10.0, 0.0, 0.0},
      los?: true
    }
  end
end
