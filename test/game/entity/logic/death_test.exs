defmodule ThistleTea.Game.Entity.Logic.DeathTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @player_flag_ghost 0x10
  @now 1_000

  defp fixture_character(opts \\ []) do
    %ThistleTea.Character{
      object: %Object{guid: 5},
      unit: %Unit{
        race: Keyword.get(opts, :race, 1),
        gender: 0,
        level: Keyword.get(opts, :level, 10),
        health: Keyword.get(opts, :health, 0),
        max_health: 100,
        power1: 0,
        max_power1: 80,
        power2: 60,
        max_power2: 100,
        power4: 0,
        max_power4: 100,
        auras: []
      },
      player: %Player{flags: Keyword.get(opts, :player_flags, 0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0},
      internal: %Internal{map: 0}
    }
  end

  defp ghost_spell_fixture do
    %Spell{
      id: 8326,
      name: "Ghost",
      school: :physical,
      duration_ms: -1,
      attributes: MapSet.new(),
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :ghost, base_points: -21, die_sides: 0, misc_value: 0},
        %Effect{index: 1, type: :apply_aura, aura: :mod_increase_speed, base_points: 24, die_sides: 1, misc_value: 0}
      ]
    }
  end

  describe "ghost?/1" do
    test "false without ghost flag" do
      refute Death.ghost?(fixture_character())
    end

    test "true with ghost flag" do
      assert Death.ghost?(fixture_character(player_flags: @player_flag_ghost))
    end
  end

  describe "alive?/1" do
    test "true for healthy character" do
      assert Death.alive?(fixture_character(health: 100))
    end

    test "false when dead" do
      refute Death.alive?(fixture_character(health: 0))
    end

    test "false for ghost with health" do
      refute Death.alive?(fixture_character(health: 1, player_flags: @player_flag_ghost))
    end
  end

  describe "ghost_spell_ids/1" do
    test "ghost spell only for most races" do
      assert Death.ghost_spell_ids(fixture_character(race: 1)) == [8326]
    end

    test "includes wisp spirit for night elves" do
      assert Death.ghost_spell_ids(fixture_character(race: 4)) == [8326, 20_584]
    end
  end

  describe "release_spirit/3" do
    test "sets health to 1 and the ghost player flag" do
      {character, _events} = Death.release_spirit(fixture_character(), [ghost_spell_fixture()], @now)

      assert character.unit.health == 1
      assert Death.ghost?(character)
      assert character.internal.broadcast_update?
    end

    test "applies ghost auras" do
      {character, _events} = Death.release_spirit(fixture_character(), [ghost_spell_fixture()], @now)

      assert [%Holder{spell: %Spell{id: 8326}}] = character.unit.auras
    end

    test "increases run speed from the ghost aura and unroots" do
      {character, events} = Death.release_spirit(fixture_character(), [ghost_spell_fixture()], @now)

      assert character.movement_block.run_speed == 7.0 * 1.25
      assert Enum.any?(events, &match?(%Event{type: :movement_speed_changed}, &1))
      assert Enum.any?(events, &match?(%Event{type: :movement_root_changed, rooted?: false}, &1))
    end
  end

  describe "resurrect/3" do
    setup do
      {ghost, _events} = Death.release_spirit(fixture_character(), [ghost_spell_fixture()], @now)
      %{ghost: ghost}
    end

    test "restores health and powers", %{ghost: ghost} do
      {character, _events} = Death.resurrect(ghost, 0.5, @now)

      assert character.unit.health == 50
      assert character.unit.power1 == 40
      assert character.unit.power2 == 0
      assert character.unit.power4 == 50
    end

    test "removes ghost auras and flag", %{ghost: ghost} do
      {character, events} = Death.resurrect(ghost, 0.5, @now)

      refute Death.ghost?(character)
      assert character.unit.auras == []
      assert character.movement_block.run_speed == 7.0
      assert character.unit.vis_flag == 0
      assert (character.player.flags &&& 0x10) == 0
      assert Enum.any?(events, &match?(%Event{type: :movement_root_changed, rooted?: false}, &1))
    end
  end

  describe "resurrection_sickness_duration_ms/1" do
    test "nil below level 11" do
      assert Death.resurrection_sickness_duration_ms(10) == nil
    end

    test "scales by level under 20" do
      assert Death.resurrection_sickness_duration_ms(11) == 60_000
      assert Death.resurrection_sickness_duration_ms(19) == 540_000
    end

    test "caps at ten minutes from level 20" do
      assert Death.resurrection_sickness_duration_ms(20) == 600_000
      assert Death.resurrection_sickness_duration_ms(60) == 600_000
    end
  end
end
