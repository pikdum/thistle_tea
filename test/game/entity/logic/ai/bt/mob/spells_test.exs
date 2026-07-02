defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob.SpellsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "try_cast/3" do
    test "initializes spell timers from initial delays without casting" do
      spell = fireball()
      entry = entry(spell.id, delay_initial_min_ms: 5_000, delay_initial_max_ms: 5_000)
      state = fixture_mob(spells: [entry], spellbook: %{spell.id => spell})

      assert {:failure, ^state, blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)
      assert blackboard.spell_timers == %{0 => 6_000}
      assert blackboard.next_spell_list_at == 2_200
    end

    test "respects the list tick cadence" do
      spell = fireball()
      entry = entry(spell.id)
      state = fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
      blackboard = %Blackboard{spell_timers: %{0 => 0}, next_spell_list_at: 2_200}

      assert {:failure, ^state, ^blackboard} = MobSpells.try_cast(state, blackboard, 1_000)
    end

    test "casts a ready spell at the current victim" do
      target_guid = hostile_player(30.0)
      spell = fireball()
      entry = entry(spell.id, delay_repeat_min_ms: 2_000, delay_repeat_max_ms: 2_000)

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_target(target_guid)

      assert {{:running, 3_000, :casting}, state, blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)

      assert %{spell: %Spell{id: 20_793}} = state.internal.casting
      assert blackboard.spell_timers == %{0 => 3_000}
      assert Enum.any?(state.internal.events, &match?(%Event{type: :spell_start, spell_id: 20_793}, &1))
    end

    test "skips casting when the target is out of range" do
      target_guid = hostile_player(100.0)
      spell = fireball()
      entry = entry(spell.id)

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_target(target_guid)

      assert {:failure, state, _blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)
      assert state.internal.casting == nil
      assert state.internal.events == []
    end

    test "completes an instant self-cast immediately" do
      spell = instant_self_buff()
      entry = entry(spell.id, cast_target: :self)
      state = fixture_mob(spells: [entry], spellbook: %{spell.id => spell})

      assert {:failure, state, _blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)
      assert state.internal.casting == nil
      assert Enum.any?(state.internal.events, &match?(%Event{type: :spell_start}, &1))
      assert Enum.any?(state.internal.events, &match?(%Event{type: :spell_go}, &1))
    end

    test "halts an in-flight move and faces the victim before a timed cast" do
      target_guid = hostile_player(20.0)
      spell = fireball()
      entry = entry(spell.id)

      state =
        fixture_mob(
          spells: [entry],
          spellbook: %{spell.id => spell},
          start_time: 0,
          duration: 10_000,
          spline_nodes: [{50.0, 0.0, 0.0}]
        )
        |> with_target(target_guid)

      assert {{:running, 3_000, :casting}, state, _blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)

      assert state.movement_block.spline_nodes == []
      assert Enum.any?(state.internal.events, &match?(%Event{type: :movement_stopped}, &1))
      {mx, my, _z, orientation} = state.movement_block.position
      assert_in_delta orientation, :math.atan2(0.0 - my, 20.0 - mx), 0.0001
    end

    test "probability failure resets the repeat timer without casting" do
      :rand.seed(:exsss, {1, 1, 1})

      target_guid = hostile_player(20.0)
      spell = fireball()

      entry =
        entry(spell.id,
          probability: 5,
          delay_repeat_min_ms: 8_000,
          delay_repeat_max_ms: 8_000
        )

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_target(target_guid)

      assert {:failure, state, blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)
      assert state.internal.casting == nil
      assert blackboard.spell_timers == %{0 => 9_000}
    end

    test "skips a not-in-melee spell when the target is adjacent" do
      target_guid = hostile_player(1.0)
      spell = fireball()
      entry = entry(spell.id, cast_flags: MapSet.new([:not_in_melee]))

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_target(target_guid)

      assert {:failure, state, _blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)
      assert state.internal.casting == nil
    end

    test "skips a self buff already present via aura_not_present" do
      spell = instant_self_buff()
      entry = entry(spell.id, cast_target: :self, cast_flags: MapSet.new([:aura_not_present]))

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_aura(spell)

      assert {:failure, state, _blackboard} = MobSpells.try_cast(state, %Blackboard{}, 1_000)
      assert state.internal.events == []
    end
  end

  describe "main-ranged stance" do
    test "a successful main-ranged cast disables combat movement and stops melee" do
      target_guid = hostile_player(25.0)
      spell = fireball()
      entry = entry(spell.id, cast_flags: MapSet.new([:main_ranged]))

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_target(target_guid)

      blackboard = %Blackboard{attack_started: true}

      assert {{:running, 3_000, :casting}, state, blackboard} = MobSpells.try_cast(state, blackboard, 1_000)

      refute Blackboard.combat_movement?(blackboard)
      refute blackboard.attack_started
      assert Enum.any?(state.internal.events, &match?(%Event{type: :attack_stop}, &1))
      assert MobSpells.holding_ranged?(state, blackboard)
    end

    test "a failed main-ranged attempt re-enables combat movement" do
      target_guid = hostile_player(100.0)
      spell = fireball()
      entry = entry(spell.id, cast_flags: MapSet.new([:main_ranged]))

      state =
        fixture_mob(spells: [entry], spellbook: %{spell.id => spell})
        |> with_target(target_guid)

      blackboard = %Blackboard{spell_timers: %{0 => 0}, combat_movement: false}

      assert {:failure, state, blackboard} = MobSpells.try_cast(state, blackboard, 1_000)
      assert state.internal.casting == nil
      assert Blackboard.combat_movement?(blackboard)
      refute MobSpells.holding_ranged?(state, blackboard)
    end
  end

  describe "hold_ranged_wait/3" do
    test "waits for the next list tick" do
      state = fixture_mob(spells: [entry(1)], spellbook: %{})
      blackboard = %Blackboard{next_spell_list_at: 1_800, combat_movement: false}

      assert {{:running, 800, :spell_list}, ^state, ^blackboard} =
               MobSpells.hold_ranged_wait(state, blackboard, 1_000)
    end
  end

  describe "next_spell_delay/3" do
    test "returns the delay until the next list tick" do
      state = fixture_mob(spells: [entry(1)], spellbook: %{})
      blackboard = %Blackboard{next_spell_list_at: 1_500}

      assert MobSpells.next_spell_delay(state, blackboard, 1_000) == 500
    end

    test "is nil for mobs without a spell list" do
      state = fixture_mob(spells: [], spellbook: %{})

      assert MobSpells.next_spell_delay(state, %Blackboard{}, 1_000) == nil
    end
  end

  defp fireball do
    %Spell{
      id: 20_793,
      name: "Fireball",
      school: :fire,
      cast_time_ms: 3_000,
      range_yards: 30.0,
      mana_cost: 0,
      power_type: 0,
      attributes: MapSet.new(),
      effects: [
        %Effect{
          index: 0,
          type: :school_damage,
          base_points: 20,
          die_sides: 1,
          implicit_target_a: :target_enemy
        }
      ]
    }
  end

  defp instant_self_buff do
    %Spell{
      id: 12_544,
      name: "Frost Armor",
      school: :frost,
      cast_time_ms: 0,
      range_yards: 0.0,
      mana_cost: 0,
      power_type: 0,
      attributes: MapSet.new(),
      effects: []
    }
  end

  defp entry(spell_id, overrides \\ []) do
    struct!(%CreatureSpell{spell_id: spell_id}, Map.new(overrides))
  end

  defp fixture_mob(opts) do
    guid = mob_guid()

    Metadata.put(guid, %{
      alive?: true,
      faction_template: defias(),
      unit_flags: 0,
      level: 5,
      attacker_count: 0
    })

    on_exit(fn -> Metadata.delete(guid) end)

    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{
        level: 5,
        faction_template: 17,
        flags: 0,
        target: 0,
        health: 100,
        max_health: 100,
        power1: 100,
        max_power1: 100
      },
      internal: %Internal{
        map: 0,
        in_combat: true,
        spellbook: Keyword.get(opts, :spellbook, %{}),
        creature: %Creature{spells: Keyword.get(opts, :spells, [])},
        movement_start_time: Keyword.get(opts, :start_time),
        movement_start_position: {0.0, 0.0, 0.0}
      },
      movement_block: %MovementBlock{
        duration: Keyword.get(opts, :duration, 0),
        position: {0.0, 0.0, 0.0, 3.0},
        spline_nodes: Keyword.get(opts, :spline_nodes, [])
      }
    }
  end

  defp with_target(%Mob{unit: unit} = state, target_guid) do
    %{state | unit: %{unit | target: target_guid}}
  end

  defp with_aura(%Mob{unit: unit} = state, %Spell{} = spell) do
    holder = %Holder{spell: spell}
    %{state | unit: %{unit | auras: [holder]}}
  end

  defp hostile_player(distance) do
    guid = player_guid()
    SpatialHash.update(:players, guid, 0, distance, 0.0, 0.0)

    Metadata.put(guid, %{
      alive?: true,
      faction_template: alliance(),
      unit_flags: 0,
      level: 5,
      combat_reach: 1.5,
      attacker_count: 1
    })

    on_exit(fn ->
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp player_guid do
    Guid.from_low_guid(:player, rem(System.unique_integer([:positive]), 0xFFFFFFF) + 1)
  end

  defp mob_guid do
    Guid.from_low_guid(:mob, 589, rem(System.unique_integer([:positive]), 0x00FFFFFF) + 1)
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end
end
