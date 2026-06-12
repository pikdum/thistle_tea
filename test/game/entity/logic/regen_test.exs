defmodule ThistleTea.Game.Entity.Logic.RegenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraEffect
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Spell

  @warrior 1
  @paladin 2
  @rogue 4
  @mage 8

  defp character(unit_attrs, internal_attrs \\ []) do
    unit =
      struct(
        %Unit{health: 100, max_health: 100, power1: 0, max_power1: 0, spirit: 50},
        unit_attrs
      )

    %Character{
      unit: unit,
      player: %Player{flags: 0},
      internal: struct(%Internal{in_combat: false}, internal_attrs)
    }
  end

  defp with_aura(entity, type, amount, opts \\ []) do
    aura = %AuraEffect{
      index: 0,
      type: type,
      amount: amount,
      misc_value: Keyword.get(opts, :misc_value),
      amplitude_ms: Keyword.get(opts, :amplitude_ms)
    }

    holder = %Holder{spell: %Spell{id: Keyword.get(opts, :spell_id, 1)}, auras: [aura]}
    %{entity | unit: %{entity.unit | auras: (entity.unit.auras || []) ++ [holder]}}
  end

  describe "tick/2" do
    test "regenerates health from spirit out of combat" do
      entity = character(class: @warrior, spirit: 50, health: 50)

      entity = Regen.tick(entity, 10_000)

      assert entity.unit.health == 90
      assert entity.internal.broadcast_update? == true
    end

    test "does not regenerate health in combat" do
      entity = character([class: @warrior, spirit: 50, health: 50], in_combat: true)

      assert Regen.tick(entity, 10_000).unit.health == 50
    end

    test "clamps health at max" do
      entity = character(class: @warrior, spirit: 200, health: 99)

      assert Regen.tick(entity, 10_000).unit.health == 100
    end

    test "does not regenerate when dead" do
      entity = character(class: @warrior, spirit: 50, health: 0)

      assert Regen.tick(entity, 10_000) == entity
    end

    test "does not regenerate as a ghost" do
      entity = character(class: @warrior, spirit: 50, health: 1)
      entity = %{entity | player: %Player{flags: 0x10}}

      assert Regen.tick(entity, 10_000) == entity
    end

    test "regenerates mana from spirit" do
      entity = character(class: @mage, spirit: 40, power_type: 0, power1: 100, max_power1: 200)

      entity = Regen.tick(entity, 10_000)

      assert entity.unit.power1 == 122
    end

    test "suppresses spirit mana regen within five seconds of spending mana" do
      entity =
        character(
          [class: @mage, spirit: 40, power_type: 0, power1: 100, max_power1: 200],
          last_mana_use_at: 8_000
        )

      assert Regen.tick(entity, 10_000).unit.power1 == 100
      assert Regen.tick(entity, 13_000).unit.power1 == 122
    end

    test "regenerates mana in combat outside the five second rule" do
      entity =
        character(
          [class: @mage, spirit: 40, power_type: 0, power1: 100, max_power1: 200],
          in_combat: true
        )

      assert Regen.tick(entity, 10_000).unit.power1 == 122
    end

    test "regenerates energy in and out of combat" do
      out_of_combat = character(class: @rogue, power_type: 3, power4: 50, max_power4: 100)
      in_combat = character([class: @rogue, power_type: 3, power4: 95, max_power4: 100], in_combat: true)

      assert Regen.tick(out_of_combat, 10_000).unit.power4 == 70
      assert Regen.tick(in_combat, 10_000).unit.power4 == 100
    end

    test "decays rage out of combat" do
      entity = character(class: @warrior, power_type: 1, power2: 30, max_power2: 1_000)

      entity = Regen.tick(entity, 10_000)

      assert entity.unit.power2 == 10
      assert Regen.tick(entity, 12_000).unit.power2 == 0
    end

    test "does not decay rage in combat" do
      entity = character([class: @warrior, power_type: 1, power2: 30, max_power2: 1_000], in_combat: true)

      assert Regen.tick(entity, 10_000).unit.power2 == 30
    end
  end

  describe "tick/2 with aura modifiers" do
    test "carries health regen fractions to the next tick" do
      entity = character(class: @paladin, spirit: 50, health: 10)

      entity = Regen.tick(entity, 10_000)
      assert entity.unit.health == 22
      assert entity.internal.health_regen_carry == 0.5

      entity = Regen.tick(entity, 12_000)
      assert entity.unit.health == 35
      assert entity.internal.health_regen_carry == 0.0
    end

    test "sitting multiplies spirit health regen by 1.5" do
      entity = character(class: @warrior, spirit: 50, health: 10, stand_state: 1)

      assert Regen.tick(entity, 10_000).unit.health == 10 + 60
    end

    test "mod_health_regen_percent scales health regen out of combat" do
      entity =
        character(class: @warrior, spirit: 50, health: 10)
        |> with_aura(:mod_health_regen_percent, 10)

      assert Regen.tick(entity, 10_000).unit.health == 10 + 44
    end

    test "mod_regen_during_combat allows a fraction of health regen in combat" do
      entity =
        character([class: @warrior, spirit: 50, health: 10], in_combat: true)
        |> with_aura(:mod_regen_during_combat, 10)

      assert Regen.tick(entity, 10_000).unit.health == 10 + 4
    end

    test "mod_health_regen_in_combat adds flat health regen even in combat" do
      entity =
        character([class: @warrior, spirit: 50, health: 10], in_combat: true)
        |> with_aura(:mod_health_regen_in_combat, 50)

      assert Regen.tick(entity, 10_000).unit.health == 10 + 20
    end

    test "food auras heal proportionally to their period out of combat only" do
      entity =
        character(class: @paladin, spirit: 0, health: 10)
        |> with_aura(:mod_regen, 20, amplitude_ms: 5_000)

      assert Regen.tick(entity, 10_000).unit.health == 18

      in_combat =
        character([class: @paladin, spirit: 0, health: 10], in_combat: true)
        |> with_aura(:mod_regen, 20, amplitude_ms: 5_000)

      assert Regen.tick(in_combat, 10_000).unit.health == 10
    end

    test "mod_power_regen adds mp5 that works during the five second rule" do
      entity =
        character(
          [class: @mage, spirit: 40, power_type: 0, power1: 100, max_power1: 500],
          last_mana_use_at: 9_000
        )
        |> with_aura(:mod_power_regen, 41, misc_value: 0)

      assert Regen.tick(entity, 10_000).unit.power1 == 100 + 16
    end

    test "mod_mana_regen_interrupt allows a fraction of spirit regen while casting" do
      entity =
        character(
          [class: @mage, spirit: 40, power_type: 0, power1: 100, max_power1: 500],
          last_mana_use_at: 9_000
        )
        |> with_aura(:mod_mana_regen_interrupt, 30)

      assert Regen.tick(entity, 10_000).unit.power1 == 100 + 6
    end

    test "evocation-style percent and interrupt auras give full boosted regen while casting" do
      entity =
        character(
          [class: @mage, spirit: 40, power_type: 0, power1: 100, max_power1: 5_000],
          last_mana_use_at: 9_000
        )
        |> with_aura(:mod_power_regen_percent, 1_500, misc_value: 0)
        |> with_aura(:mod_mana_regen_interrupt, 100)

      assert Regen.tick(entity, 10_000).unit.power1 == 100 + trunc(22.5 * 16)
    end

    test "mod_power_regen_percent scales energy regen" do
      entity =
        character(class: @rogue, power_type: 3, power4: 10, max_power4: 100)
        |> with_aura(:mod_power_regen_percent, 100, misc_value: 3)

      assert Regen.tick(entity, 10_000).unit.power4 == 50
    end

    test "interrupt_regen prevents rage decay out of combat" do
      entity =
        character(class: @warrior, power_type: 1, power2: 30, max_power2: 1_000)
        |> with_aura(:interrupt_regen, 0)

      assert Regen.tick(entity, 10_000).unit.power2 == 30
    end
  end

  describe "tick/2 for creatures" do
    defp mob(unit_attrs, internal_attrs \\ []) do
      {regenerate_stats, internal_attrs} = Keyword.pop(internal_attrs, :regenerate_stats)

      internal =
        struct(
          %Internal{in_combat: false, creature: %Creature{regenerate_stats: regenerate_stats}},
          internal_attrs
        )

      %Mob{
        unit: struct(%Unit{health: 300, max_health: 300}, unit_attrs),
        internal: internal
      }
    end

    test "regenerates a third of max health out of combat" do
      entity = mob(health: 50)

      entity = Regen.tick(entity, 10_000)

      assert entity.unit.health == 150
      assert entity.internal.broadcast_update? == true
      assert Regen.tick(entity, 15_000).unit.health == 250
    end

    test "does not regenerate in combat" do
      entity = mob([health: 50], in_combat: true)

      assert Regen.tick(entity, 10_000).unit.health == 50
    end

    test "regenerates a third of max mana out of combat" do
      entity = mob(health: 300, power1: 0, max_power1: 90)

      assert Regen.tick(entity, 10_000).unit.power1 == 30
    end

    test "does not regenerate when dead" do
      entity = mob(health: 0)

      assert Regen.tick(entity, 10_000) == entity
    end

    test "respects the regenerate_stats flags" do
      no_regen = mob([health: 50, power1: 0, max_power1: 90], regenerate_stats: 0)
      health_only = mob([health: 50, power1: 0, max_power1: 90], regenerate_stats: 1)

      assert Regen.tick(no_regen, 10_000) == no_regen

      health_only = Regen.tick(health_only, 10_000)
      assert health_only.unit.health == 150
      assert health_only.unit.power1 == 0
    end

    test "uses the 5 second creature tick interval" do
      assert Regen.tick_ms(mob([])) == 5_000
      assert Regen.tick_ms(character(class: @mage)) == 2_000
    end

    test "needs_regen?/1 for creatures" do
      assert Regen.needs_regen?(mob(health: 50))
      assert Regen.needs_regen?(mob(health: 300, power1: 0, max_power1: 90))
      refute Regen.needs_regen?(mob(health: 300))
      refute Regen.needs_regen?(mob([health: 50], in_combat: true))
      refute Regen.needs_regen?(mob(health: 0))
      refute Regen.needs_regen?(mob([health: 50], regenerate_stats: 0))
    end
  end

  describe "needs_regen?/1" do
    test "false when health and power are full" do
      refute Regen.needs_regen?(character(class: @mage, power_type: 0, power1: 200, max_power1: 200))
    end

    test "true when health is missing" do
      assert Regen.needs_regen?(character(class: @mage, health: 50))
    end

    test "true when mana is missing" do
      assert Regen.needs_regen?(character(class: @mage, power_type: 0, power1: 100, max_power1: 200))
    end

    test "true when energy is missing" do
      assert Regen.needs_regen?(character(class: @rogue, power_type: 3, power4: 50, max_power4: 100))
    end

    test "true while rage remains" do
      assert Regen.needs_regen?(character(class: @warrior, power_type: 1, power2: 10, max_power2: 1_000))
      refute Regen.needs_regen?(character(class: @warrior, power_type: 1, power2: 0, max_power2: 1_000))
    end

    test "false when dead or ghost" do
      refute Regen.needs_regen?(character(class: @warrior, health: 0))

      ghost = character(class: @warrior, health: 1)
      refute Regen.needs_regen?(%{ghost | player: %Player{flags: 0x10}})
    end
  end

  describe "under_five_second_rule?/2" do
    test "tracks the window after spending mana" do
      entity = character([class: @mage], last_mana_use_at: 8_000)

      assert Regen.under_five_second_rule?(entity, 12_999)
      refute Regen.under_five_second_rule?(entity, 13_000)
      refute Regen.under_five_second_rule?(character([class: @mage], []), 13_000)
    end
  end
end
