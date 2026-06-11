defmodule ThistleTea.Game.Entity.Logic.RegenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Regen

  @warrior 1
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
