defmodule ThistleTea.Game.Entity.Logic.Aura.PercentStatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "apply_spell/5" do
    test "refreshes without compounding and restores stats on expiry", %{character: character} do
      {active, _} = Aura.apply_spell(character, 1, 60, spell(), 100)
      assert active.unit.strength == 120
      assert active.unit.agility == 120
      assert active.unit.max_health == 2120
      assert active.unit.max_power1 == 2520
      assert active.unit.attack_power == 110
      assert active.player.crit_percentage == CombatRatings.melee_crit_chance(8, 60, 120)
      assert active.player.dodge_percentage == CombatRatings.dodge_chance(8, 60, 120)
      assert active.internal.broadcast_update?

      {refreshed, _} = Aura.apply_spell(active, 1, 60, spell(), 500)
      assert refreshed.unit.strength == 120
      assert length(refreshed.unit.auras) == 1
      {still_active, _} = Aura.expire_due(refreshed, 1100)
      assert still_active.unit.strength == 120
      {expired, _} = Aura.expire_due(still_active, 1500)
      assert restored_stats(expired) == restored_stats(character)
    end

    test "cancel and death restore the canonical stats", %{character: character} do
      {active, _} = Aura.apply_spell(character, 1, 60, spell(), 100)
      {cancelled, _} = Aura.cancel_spell(active, spell().id, 200)
      assert restored_stats(cancelled) == restored_stats(character)

      dead = Core.take_damage(active, active.unit.health, 200)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
      assert restored_stats(dead) == restored_stats(character)
    end

    test "penalties clamp resources and removal does not refill them", %{character: character} do
      sickness = %{
        spell()
        | effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_percent_stat, base_points: -75, misc_value: -1}]
      }

      full = %{
        character
        | unit: %{character.unit | health: character.unit.max_health, power1: character.unit.max_power1}
      }

      {sick, _} = Aura.apply_spell(full, 1, 60, sickness, 100)
      assert sick.unit.stamina == 25
      assert sick.unit.health == 1170
      assert sick.unit.power1 == 1095
      {recovered, _} = Aura.expire_due(sick, 1100)
      assert restored_stats(recovered) == restored_stats(character)
      assert recovered.unit.health == 1170
      assert recovered.unit.power1 == 1095
    end
  end

  defp character(_context) do
    unit =
      Stats.recompute(%Unit{
        class: 8,
        level: 60,
        base_strength: 100,
        base_agility: 100,
        base_stamina: 100,
        base_intellect: 100,
        base_spirit: 100,
        base_health: 1100,
        base_mana: 1000,
        health: 100,
        power1: 100,
        auras: []
      })

    character = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{character: CombatRatings.sync(character)}
  end

  defp spell do
    %Spell{
      id: 26_035,
      duration_ms: 1000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_percent_stat, base_points: 20, misc_value: -1}]
    }
  end

  defp restored_stats(character) do
    {Map.take(character.unit, [
       :strength,
       :agility,
       :stamina,
       :intellect,
       :spirit,
       :max_health,
       :max_power1,
       :attack_power
     ]), character.player.crit_percentage, character.player.dodge_percentage}
  end
end
