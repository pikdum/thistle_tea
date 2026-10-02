defmodule ThistleTea.Game.World.Loader.MobVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.DBC
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.SpatialGrid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Mob.Batch
  alias ThistleTea.Game.World.Loader.Mob.Builder, as: MobBuilder
  alias ThistleTea.Test.Unique

  @moduletag :dbc_db

  describe "load_creature/1" do
    test "loads Vincent's point movement and arrival callback" do
      events = mob(4444).internal.creature.ai_events
      arrival = Enum.find(events, &(&1.event_type == :movement_inform))
      assert {arrival.param1, arrival.param2} == {9, 1}
      assert [[%ScriptStep{command: :stand_state, datalong: 7}]] = arrival.actions
      retreat = events |> Enum.find(&(&1.event_type == :hp)) |> Map.fetch!(:actions) |> List.flatten()
      assert %ScriptStep{datalong3: 68, datalong4: 3, dataint: 1} = Enum.find(retreat, &(&1.command == :move_to))
      cleanup = Enum.find(events, &(&1.event_type == :timer_in_combat))
      assert [[%ScriptStep{command: :enter_evade}]] = cleanup.actions
    end

    test "loads Defias Pillager spell list and derived stats" do
      mob = mob(589)

      assert Enum.map(mob.internal.creature.spells, & &1.spell_id) == [19_816]
      assert mob.unit.level in 14..15
      assert mob.unit.max_health in 220..320
      assert mob.unit.min_damage > 0
      assert mob.unit.max_damage > mob.unit.min_damage
      assert mob.unit.bounding_radius in [0.208, 0.306]
      assert mob.unit.combat_reach == 1.5
      assert mob.internal.creature.addon_auras == []
    end

    test "rolls Defias Pillager's charm abilities with their cooldown ranges" do
      mob = mob(589)

      assert mob.internal.creature.charm_spells == [20_793, 12_544]
      assert mob.internal.spellbook[20_793].recovery_time_ms == 0
      assert mob.internal.spellbook[12_544].recovery_time_ms in 9_000..12_000
    end

    test "loads Defias Pillager EventAI events with resolved scripts" do
      mob = mob(589)
      events = mob.internal.creature.ai_events

      assert [timer_ooc, aggro, hp] = events

      assert timer_ooc.event_type == :timer_ooc
      assert timer_ooc.repeatable?
      assert [[%{command: :cast_spell, datalong: 12_544, target_self?: true}]] = timer_ooc.actions

      assert aggro.event_type == :aggro
      assert aggro.chance == 15
      assert [[%{command: :talk, texts: [_, _]}]] = aggro.actions

      assert hp.event_type == :hp
      assert hp.param1 == 15
      assert [[%{command: :flee}]] = hp.actions

      assert Map.has_key?(mob.internal.spellbook, 12_544)
    end

    test "replaces the lazy peon's EventAI with its script port" do
      mob = mob(10_556)
      events = mob.internal.creature.ai_events

      assert Enum.map(events, & &1.event_type) == [:timer_ooc, :hit_by_spell, :movement_inform, :reached_home]

      [timed] =
        events
        |> Enum.find(&(&1.event_type == :hit_by_spell))
        |> Map.fetch!(:actions)
        |> List.flatten()
        |> Enum.filter(&(&1.command == :start_script))

      assert %ScriptStep{texts: [text]} =
               timed.sub_scripts |> Map.values() |> List.flatten() |> Enum.find(&(&1.command == :talk))

      assert text.text =~ "get back to work"
      assert Map.has_key?(mob.internal.spellbook, 17_743)
    end

    test "attaches waypoint movement scripts with resolved texts" do
      mob =
        %Mangos.Creature{
          guid: 108,
          id: 6_175,
          map: 0,
          position_x: 0.0,
          position_y: 0.0,
          position_z: 0.0,
          orientation: 0.0
        }
        |> MobLoader.load_creature()
        |> MobBuilder.build()

      point = mob.internal.spawn.waypoint_route.points[7]

      assert [%{command: :talk, texts: [%{text: text} | _] = texts}] = point.script_steps
      assert length(texts) == 4
      assert is_binary(text) and text != ""
    end

    test "resolves the Defias Thug guid-scoped emote condition tree and settles it per spawn" do
      thug = creature(38)

      emote_event = Enum.find(thug.ai_events, &(&1.condition_id == 3_804))

      assert %Condition{type: :or, children: [left, right]} = emote_event.condition
      assert %Condition{type: :db_guid, value1: 80_152} = left
      assert %Condition{type: :db_guid, value1: 80_151} = right

      refute Enum.any?(MobBuilder.build(thug).internal.creature.ai_events, &(&1.condition_id == 3_804))

      assert %{condition: nil} =
               Enum.find(
                 MobBuilder.build(%{thug | guid: 80_152}).internal.creature.ai_events,
                 &(&1.condition_id == 3_804)
               )
    end

    test "resolves start_script generic sub-scripts with texts" do
      mob = mob(550)

      aggro = Enum.find(mob.internal.creature.ai_events, &(&1.event_type == :aggro))

      assert [[%ScriptStep{command: :start_script} = step]] = aggro.actions
      assert ScriptStep.start_script_options(step) == [{55_001, 50}, {55_002, 50}]

      assert [%ScriptStep{command: :talk, texts: [%{text: text} | _] = texts}] = step.sub_scripts[55_001]
      assert length(texts) == 4
      assert is_binary(text) and text != ""
      assert [%ScriptStep{command: :talk, texts: [_ | _]}] = step.sub_scripts[55_002]
    end

    test "resolves the Eastvale peasant supervisor buddy by spawn guid" do
      mob =
        %Mangos.Creature{
          guid: 81_249,
          id: 11_328,
          map: 0,
          position_x: 0.0,
          position_y: 0.0,
          position_z: 0.0,
          orientation: 0.0
        }
        |> MobLoader.load_creature()
        |> MobBuilder.build()

      supervisor_guid = Guid.from_low_guid(:mob, 10_616, 81_251)

      steps =
        mob.internal.spawn.waypoint_route.points
        |> Map.values()
        |> Enum.flat_map(& &1.script_steps)

      start_script = Enum.find(steps, &(&1.command == :start_script and &1.target_type == :creature_with_guid))

      assert start_script.buddy_guid == supervisor_guid
      assert start_script.swap_final?

      assert [%ScriptStep{command: :talk, texts: texts}, %ScriptStep{command: :emote}] =
               start_script.sub_scripts[1_061_601]

      assert Enum.any?(texts, &String.starts_with?(&1.text, "Daylight is still upon us"))
    end

    test "loads template auras from creature_template" do
      mob = mob(619)

      assert Enum.map(mob.internal.creature.addon_auras, & &1.id) == [12_544]
    end

    test "decodes vmangos creature spell cast targets" do
      targets =
        701
        |> mob()
        |> then(& &1.internal.creature.spells)
        |> Map.new(&{&1.spell_id, &1.cast_target})

      assert targets[11_986] == :friendly_injured
      assert targets[4_979] == :friendly_missing_buff
    end

    test "loads hostile and friendly totem spells from creature templates" do
      assert [%{spell_id: 22_048, cast_target: :victim, cast_flags: attack_flags}] =
               mob(2_523).internal.creature.spells

      assert [%{spell_id: 5_672, cast_target: :self, cast_flags: aura_flags}] =
               mob(3_527).internal.creature.spells

      refute MapSet.member?(attack_flags, :aura_not_present)
      assert MapSet.member?(aura_flags, :aura_not_present)
    end
  end

  describe "Batch.load/1" do
    test "loads a populated cell with a bounded query count" do
      rows =
        0
        |> Mangos.Creature.query_bounds(SpatialGrid.cell_bounds({WorldRef.open(0), -71, -2}), [])
        |> Mangos.Repo.all()

      counter = :counters.new(1, [:atomics])
      handler_id = "mob-batch-query-count-#{Unique.integer()}"

      events = [
        Mangos.Repo.config()[:telemetry_prefix] ++ [:query],
        DBC.config()[:telemetry_prefix] ++ [:query]
      ]

      :ok =
        :telemetry.attach_many(
          handler_id,
          events,
          fn _event, _measurements, _metadata, counter ->
            :counters.add(counter, 1, 1)
          end,
          counter
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert loaded = Batch.load(rows)
      assert length(loaded) == length(rows)
      assert length(loaded) > 25
      assert :counters.get(counter, 1) <= 20
    end
  end

  defp mob(entry), do: entry |> creature() |> MobBuilder.build()

  defp creature(entry) do
    %Mangos.Creature{
      guid: entry,
      id: entry,
      map: 0,
      position_x: 0.0,
      position_y: 0.0,
      position_z: 0.0,
      orientation: 0.0
    }
    |> MobLoader.load_creature()
  end
end
