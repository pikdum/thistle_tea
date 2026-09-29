defmodule ThistleTea.Game.Core.AI.TickTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.Tick
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.Reactive
  alias ThistleTea.Game.Core.Combat.ReactiveWindow
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Spell.Cast

  describe "mob_delay/3" do
    test "wakes at totem expiry even when behavior and aura ticks are later" do
      entity = fixture()
      entity = %{entity | internal: %{entity.internal | totem: %Totem{expires_at: 1_050}}}
      assert Tick.mob_delay(entity, {:running, 2_000}, 1_000) == 50
      assert Tick.mob_delay(entity, {:running, 2_000}, 1_100) == 0
    end

    test "wakes for a scripted arrival before a long behavior sleep" do
      entity = %{fixture() | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}}
      event = %Effects.MovementInform{motion_type: 9, point_id: 1}
      entity = Movement.move_along_path(entity, [{1.0, 0.0, 0.0}], [velocity: 10.0, movement_inform: event], 1_000)
      assert Tick.mob_delay(entity, {:running, 30_000}, 1_000) == 100
    end

    test "uses the tree's running delay" do
      assert Tick.mob_delay(fixture(), {:running, 250}, 1_000) == 250
    end

    test "uses reason-tagged running delays" do
      assert Tick.mob_delay(fixture(), {:running, 250, :movement}, 1_000) == 250
    end

    test "honors long self-paced sleeps" do
      assert Tick.mob_delay(fixture(), {:running, 30_000}, 1_000) == 30_000
    end

    test "defaults without a self-paced delay" do
      assert Tick.mob_delay(fixture(), :running, 1_000) == 100
      assert Tick.mob_delay(fixture(), :success, 1_000) == 100
    end

    test "a behavior waiting on messages leaves no wake unless upkeep needs one" do
      assert Tick.mob_delay(fixture(), {:running, :infinity, :idle}, 1_000) == nil

      entity = %{fixture() | internal: %{fixture().internal | totem: %Totem{expires_at: 1_050}}}
      assert Tick.mob_delay(entity, {:running, :infinity, :idle}, 1_000) == 50
    end
  end

  describe "needs_tick?/1" do
    test "ticks while casting" do
      assert Tick.needs_tick?(fixture(casting: %Cast{}))
    end

    test "ticks while auto shot is active" do
      assert Tick.needs_tick?(fixture(auto_shot: %{target_guid: 42}))
    end

    test "ticks while in combat with a target" do
      assert Tick.needs_tick?(fixture(in_combat: true, target: 42))
    end

    test "ticks while in combat without a target" do
      assert Tick.needs_tick?(fixture(in_combat: true))
    end

    test "ticks an active melee victim before combat even after selection is cleared" do
      character =
        fixture(
          blackboard: Blackboard.enable_auto_attack(Blackboard.new(), %TargetRef{guid: 42}),
          target: 0
        )

      assert Tick.needs_tick?(character)
    end

    test "ticks with active auras" do
      assert Tick.needs_tick?(fixture(auras: [:aura]))
    end

    test "ticks while regenerating" do
      assert Tick.needs_tick?(fixture(health: 10))
    end

    test "idles at full resources with nothing active" do
      refute Tick.needs_tick?(fixture())
    end
  end

  describe "player_delay/3" do
    test "wakes for each reactive expiry even after combat ends" do
      character = fixture()

      character = %{
        character
        | internal: %{
            character.internal
            | defense_window: %ReactiveWindow{target_guid: 77, expires_at: 1_050},
              hunter_parry_window: %ReactiveWindow{target_guid: 78, expires_at: 1_075}
          }
      }

      assert Tick.needs_tick?(character)
      assert Tick.player_delay(character, {:running, 2_000}, 1_000) == 50

      character = Reactive.tick(character, 1_050)
      assert character.unit.aura_state == 0x40
      assert Tick.needs_tick?(character)
      assert Tick.player_delay(character, {:running, 2_000}, 1_050) == 25
      assert Tick.player_delay(character, {:running, 2_000}, 1_080) == 0

      character = Reactive.tick(character, 1_080)
      assert character.unit.aura_state == 0
      refute Tick.needs_tick?(character)
    end

    test "Overpower's temporary combo target has an expiry deadline" do
      character = fixture()
      character = %{character | internal: %{character.internal | combo_expires_at: 1_050}}
      assert Tick.needs_tick?(character)
      assert Tick.player_delay(character, {:running, 2_000}, 1_000) == 50
    end

    test "uses the tree's running delay when no regen is due sooner" do
      character = fixture(in_combat: true, target: 42)

      assert Tick.player_delay(character, {:running, 400}, 1_000) == 400
    end

    test "uses reason-tagged player running delays" do
      character = fixture(in_combat: true, target: 42)

      assert Tick.player_delay(character, {:running, 400, :attack}, 1_000) == 400
    end

    test "wakes for regen before a long running delay" do
      character =
        fixture(
          health: 10,
          blackboard: %Blackboard{
            maintenance: %Blackboard.Maintenance{next_regen_at: 1_200}
          }
        )

      assert Tick.player_delay(character, {:running, 2_000}, 1_000) == 200
    end

    test "active combat wakes for the next combat check" do
      character = fixture(in_combat: true, target: 42)

      assert Tick.player_delay(character, :success, 1_000) == 1_000
      assert Tick.player_delay(character, :success, 1_250) == 750
    end

    test "a long aura deadline cannot postpone the combat check" do
      buff = %Holder{expires_at: 1_801_000}

      assert Tick.player_delay(fixture(in_combat: true, auras: [buff]), :running, 1_250) == 750
      assert Tick.player_delay(fixture(auras: [buff]), :running, 1_250) == 1_799_750
    end

    test "a held combat window wakes at its expiry" do
      character = fixture(in_combat: true, last_hostile_time: 1_000, combat_timeout_ms: 5_000)

      assert Tick.player_delay(character, {:running, 30_000}, 1_250) == 4_750
    end

    test "passive regen sleeps until the next regen tick" do
      character =
        fixture(
          health: 10,
          blackboard: %Blackboard{
            maintenance: %Blackboard.Maintenance{next_regen_at: 3_500}
          }
        )

      assert Tick.player_delay(character, :success, 1_000) == 2_500
    end
  end

  defp fixture(opts \\ []) do
    %Character{
      unit: %Unit{
        health: Keyword.get(opts, :health, 100),
        max_health: 100,
        power1: 100,
        max_power1: 100,
        target: Keyword.get(opts, :target, 0),
        auras: Keyword.get(opts, :auras, [])
      },
      internal: %Internal{
        casting: Keyword.get(opts, :casting),
        auto_shot: Keyword.get(opts, :auto_shot),
        in_combat: Keyword.get(opts, :in_combat, false),
        last_hostile_time: Keyword.get(opts, :last_hostile_time),
        combat_timeout_ms: Keyword.get(opts, :combat_timeout_ms, 5_000),
        blackboard: Keyword.get(opts, :blackboard)
      }
    }
  end
end
