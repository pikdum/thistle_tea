defmodule ThistleTea.Game.Entity.Data.ScriptStepTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ScriptStep

  describe "build/1" do
    test "decodes commands, delays, and target flags" do
      step =
        ScriptStep.build(%{
          id: 100,
          delay: 3,
          priority: 1,
          command: 15,
          datalong: 12_544,
          datalong2: 2,
          datalong3: 0,
          datalong4: 0,
          dataint: 0,
          dataint2: 0,
          dataint3: 0,
          dataint4: 0,
          target_type: 0,
          target_param1: 0,
          target_param2: 0,
          data_flags: 0x04,
          x: 1.0,
          y: 2.0,
          z: 3.0,
          o: 4.0,
          condition_id: 0
        })

      assert step.command == :cast_spell
      assert step.delay_ms == 3_000
      assert step.target_type == :provided
      assert step.target_self?
      refute step.swap_initial?
      refute step.swap_final?
      assert step.position == {1.0, 2.0, 3.0, 4.0}
      assert ScriptStep.cast_spell_id(step) == 12_544
    end

    test "decodes taxi commands and nearest-player targets" do
      step =
        ScriptStep.build(%{
          id: 5,
          delay: 0,
          priority: 0,
          command: 30,
          datalong: 0,
          datalong2: 0,
          datalong3: 0,
          datalong4: 0,
          dataint: 0,
          dataint2: 0,
          dataint3: 0,
          dataint4: 0,
          target_type: 25,
          target_param1: 0,
          target_param2: 0,
          data_flags: 0,
          x: 0.0,
          y: 0.0,
          z: 0.0,
          o: 0.0,
          condition_id: 0
        })

      assert step.command == :send_taxi_path
      assert step.target_type == :nearest_player

      assert row(30) |> Map.put(:target_type, 26) |> ScriptStep.build() |> Map.fetch!(:target_type) ==
               :nearest_hostile_player

      assert row(30) |> Map.put(:target_type, 27) |> ScriptStep.build() |> Map.fetch!(:target_type) ==
               :nearest_friendly_player
    end

    test "decodes quest credit commands" do
      assert ScriptStep.build(row(7)).command == :quest_explored
      assert ScriptStep.build(row(8)).command == :kill_credit
      assert ScriptStep.build(row(9)).command == :respawn_game_object
      assert ScriptStep.build(row(11)).command == :open_door
      assert ScriptStep.build(row(12)).command == :close_door
      assert ScriptStep.build(row(13)).command == :activate_object
      assert ScriptStep.build(row(17)).command == :create_item
      assert ScriptStep.build(row(19)).command == :set_equipment
      assert ScriptStep.build(row(20)).command == :movement
      assert ScriptStep.build(row(4)).command == :modify_flags
      assert ScriptStep.build(row(5)).command == :interrupt_casts
      assert ScriptStep.build(row(31)).command == :terminate_script
      assert ScriptStep.build(row(32)).command == :terminate_condition
      assert ScriptStep.build(row(22)).command == :set_faction
      assert ScriptStep.build(row(29)).command == :modify_threat
      assert ScriptStep.build(row(34)).command == :set_home_position
      assert ScriptStep.build(row(41)).command == :remove_object
      assert ScriptStep.build(row(42)).command == :set_melee_attack
      assert ScriptStep.build(row(43)).command == :set_combat_movement
      assert ScriptStep.build(row(50)).command == :call_for_help
      assert ScriptStep.build(row(51)).command == :set_sheath
      assert ScriptStep.build(row(52)).command == :invincibility
      assert ScriptStep.build(row(60)).command == :start_waypoints
      assert ScriptStep.build(row(61)).command == :start_map_event
      assert ScriptStep.build(row(69)).command == :edit_map_event
      assert ScriptStep.build(row(70)).command == :fail_quest
      assert ScriptStep.build(row(71)).command == :respawn_creature
      assert ScriptStep.build(row(73)).command == :combat_stop
      assert ScriptStep.build(row(74)).command == :add_aura
      assert ScriptStep.build(row(76)).command == :summon_object
      assert ScriptStep.build(row(80)).command == :set_game_object_state
      assert ScriptStep.build(row(81)).command == :despawn_game_object
      assert ScriptStep.build(row(82)).command == :load_game_object_spawn
      assert ScriptStep.build(row(83)).command == :quest_credit
      assert ScriptStep.build(row(85)).command == :send_script_event
      assert ScriptStep.build(row(87)).command == :reset_door_or_button
      assert ScriptStep.build(row(89)).command == :play_custom_animation
    end

    test "decodes instance data command modes and rejects invalid modes" do
      assert instance_data_step(0) == {:set_instance_data, :raw}
      assert instance_data_step(1) == {:set_instance_data, :increment}
      assert instance_data_step(2) == {:set_instance_data, :decrement}

      invalid = row(37) |> Map.put(:datalong3, 3) |> ScriptStep.build()
      assert invalid.command == {:unsupported, 37}
      assert ScriptStep.instance_data_command(invalid) == {:error, :unsupported}
    end

    test "decodes game object target selectors" do
      nearest = row(13) |> Map.put(:target_type, 13) |> ScriptStep.build()
      by_guid = row(13) |> Map.put(:target_type, 14) |> ScriptStep.build()

      assert nearest.target_type == :nearest_game_object_with_entry
      assert by_guid.target_type == :game_object_with_guid
    end

    test "decodes map event target selectors" do
      source = row(0) |> Map.put(:target_type, 22) |> ScriptStep.build()
      target = row(0) |> Map.put(:target_type, 23) |> ScriptStep.build()
      extra = row(0) |> Map.put(:target_type, 24) |> ScriptStep.build()

      assert source.target_type == :map_event_source
      assert target.target_type == :map_event_target
      assert extra.target_type == :map_event_extra_target
    end

    test "decodes remaining runtime-backed target selectors" do
      assert row(0) |> Map.put(:target_type, 6) |> ScriptStep.build() |> Map.fetch!(:target_type) == :hostile_nearest
      assert row(0) |> Map.put(:target_type, 7) |> ScriptStep.build() |> Map.fetch!(:target_type) == :hostile_farthest
      assert row(0) |> Map.put(:target_type, 9) |> ScriptStep.build() |> Map.fetch!(:target_type) == :owner

      assert row(0) |> Map.put(:target_type, 29) |> ScriptStep.build() |> Map.fetch!(:target_type) ==
               :random_game_object_with_entry
    end
  end

  describe "condition_ids/1" do
    test "collects command and map-event condition ids" do
      start = %ScriptStep{command: :start_map_event, condition_id: 5, dataint: 10, dataint3: 11}
      remove = %ScriptStep{command: :remove_map_event_target, datalong2: 12}
      terminate = %ScriptStep{command: :terminate_condition, datalong: 13}

      assert ScriptStep.condition_ids(start) == [5, 10, 11]
      assert ScriptStep.condition_ids(remove) == [12]
      assert ScriptStep.condition_ids(terminate) == [13]
    end
  end

  describe "teleport_to/1" do
    test "preserves the declared map, options, pose, and routing fields" do
      step =
        row(6)
        |> Map.merge(%{
          datalong: 0,
          datalong2: 9,
          target_type: 11,
          data_flags: 0x02,
          x: 1.25,
          y: -2.5,
          z: 3.75,
          o: 0.0
        })
        |> ScriptStep.build()

      assert step.command == :teleport_to
      assert step.target_type == :creature_with_guid
      assert step.swap_final?

      assert {:ok, teleport} = ScriptStep.teleport_to(step)
      assert teleport == %{declared_map_id: 0, options: 9, position: {1.25, -2.5, 3.75, 0.0}}
    end

    test "fails closed for malformed payloads" do
      valid = %ScriptStep{command: :teleport_to, datalong: 329, datalong2: 0, position: {1.0, 2.0, 3.0, 4.0}}

      for invalid <- [
            %{valid | datalong: -1},
            %{valid | datalong: 1.0},
            %{valid | datalong2: -1},
            %{valid | datalong2: 1.0},
            %{valid | position: nil},
            %{valid | position: {1.0, 2.0, :nan, 4.0}}
          ] do
        assert ScriptStep.teleport_to(invalid) == {:error, :unsupported}
      end

      assert ScriptStep.teleport_to(%{valid | command: :move_to}) == {:error, :unsupported}
    end
  end

  describe "talk_text_ids/1" do
    test "collects the non-zero broadcast text ids of talk steps" do
      step = %ScriptStep{command: :talk, dataint: 1_866, dataint2: 1_867, dataint3: 0, dataint4: 0}

      assert ScriptStep.talk_text_ids(step) == [1_866, 1_867]
      assert ScriptStep.talk_text_ids(%ScriptStep{command: :emote, dataint: 5}) == []
    end
  end

  describe "emote_ids/1" do
    test "collects the non-zero emote ids of emote steps" do
      step = %ScriptStep{command: :emote, datalong: 11, datalong2: 0}

      assert ScriptStep.emote_ids(step) == [11]
      assert ScriptStep.emote_ids(%ScriptStep{command: :talk, datalong: 11}) == []
    end
  end

  defp row(command) do
    %{
      id: 5,
      delay: 0,
      priority: 0,
      command: command,
      datalong: 0,
      datalong2: 0,
      datalong3: 0,
      datalong4: 0,
      dataint: 0,
      dataint2: 0,
      dataint3: 0,
      dataint4: 0,
      target_type: 0,
      target_param1: 0,
      target_param2: 0,
      data_flags: 0,
      x: 0.0,
      y: 0.0,
      z: 0.0,
      o: 0.0,
      condition_id: 0
    }
  end

  defp instance_data_step(mode) do
    step =
      row(37)
      |> Map.merge(%{datalong: 7, datalong2: 2, datalong3: mode})
      |> ScriptStep.build()

    assert {:ok, %{field: 7, value: 2, mode: decoded_mode}} = ScriptStep.instance_data_command(step)
    {step.command, decoded_mode}
  end
end
