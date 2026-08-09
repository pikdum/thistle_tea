defmodule ThistleTea.Game.CreatureTeleportContentTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  test "all seven imported rows execute as exact same-copy creature teleports" do
    rows = [
      {184_202, 0, {2942.58, -1390.09, 167.421, 4.2586}},
      {144_507, 0, {-3660.6, -717.77, 28.156, 3.05292}},
      {144_611, 0, {-3628.43, -719.022, 10.8226, 0.0}},
      {1_043_504, 0, {4068.74, -3535.97, 122.825, 2.47837}},
      {4_341, 0, {-8408.25, 451.896, 123.76, 5.52986}},
      {10_917, 329, {4032.73, -3366.51, 115.063, 5.42797}},
      {144_502, 0, {-3666.06, -718.628, 9.95469, 0.0}}
    ]

    Enum.with_index(rows, 1)
    |> Enum.each(fn {{script_id, declared_map_id, destination}, copy_id} ->
      world = WorldRef.instance(329, copy_id)
      source = mob(script_id, world, {1.0, 2.0, 3.0, 0.5})
      step = teleport_step(script_id, declared_map_id, destination)
      {teleported, _blackboard} = Script.run(source, Blackboard.new(), [step], nil, 1_000)

      assert teleported.internal.world == world
      assert teleported.movement_block.position == destination
      assert [%Effects.CreatureTeleported{} = effect] = teleported.internal.events
      assert effect.world == world
      assert effect.position == destination
      assert effect.declared_map_id == declared_map_id
    end)
  end

  test "Aurius receives the Baron-forwarded delayed sequence without changing copies" do
    world = WorldRef.instance(329, 41)
    aurius = mob(10_917, world, {3680.53, -3643.8, 140.027, 5.46288})
    baron = mob(10_440, world, {4032.0, -3390.0, 119.0, 0.0})
    original_baron_position = baron.movement_block.position

    parent = %ScriptStep{
      script_id: 1_044_001,
      command: :start_script,
      datalong: 10_917,
      dataint: 100,
      target_type: :creature_with_guid,
      target_param1: 53_297,
      buddy_guid: aurius.object.guid,
      swap_final?: true,
      sub_scripts: %{10_917 => aurius_steps()}
    }

    {baron, _blackboard} = Script.run(baron, Blackboard.new(), [parent], nil, 0)
    assert baron.movement_block.position == original_baron_position
    assert [%Effects.ForwardScriptSteps{steps: [forwarded], target_guid: target_guid}] = baron.internal.events
    assert target_guid == aurius.object.guid
    assert forwarded.delay_ms == 0
    assert forwarded.target_type == :provided
    refute forwarded.swap_final?

    {aurius, blackboard} = Script.run(aurius, Blackboard.new(), [forwarded], baron.object.guid, 0)
    {aurius, [at_ten]} = take_schedules(aurius)
    assert at_ten.duration_ms == 10_000

    {aurius, blackboard} = Script.run(aurius, blackboard, at_ten.steps, at_ten.target_guid, 10_000)
    assert aurius.unit.faction_template == 250
    assert aurius.unit.npc_flags == 0
    assert aurius.unit.stand_state == 0
    assert aurius.movement_block.position == {3680.53, -3643.8, 140.027, 5.46288}
    {aurius, [at_eleven]} = take_schedules(aurius)

    {aurius, blackboard} = Script.run(aurius, blackboard, at_eleven.steps, at_eleven.target_guid, 11_000)
    assert aurius.internal.world == world
    assert aurius.movement_block.position == {4032.73, -3366.51, 115.063, 5.42797}
    assert [%Effects.CreatureTeleported{} = teleport, %Effects.ScriptSteps{} = at_twelve] = aurius.internal.events
    assert teleport.world == world
    assert teleport.declared_map_id == 329
    assert aurius.internal.spawn.position == {3680.53, -3643.8, 140.027}
    {aurius, _effects} = Effects.drain(aurius)

    {aurius, blackboard} = Script.run(aurius, blackboard, at_twelve.steps, at_twelve.target_guid, 12_000)
    assert [%{destination: destination}] = aurius.internal.navigation_intents
    assert destination == {4031.0, -3346.89, 115.107}
    assert aurius.internal.spawn.position == {4033.1, -3349.29, 115.107}
    assert aurius.internal.spawn.home_orientation == 6.0
    assert Enum.any?(aurius.internal.events, &is_struct(&1, Effects.MonsterTalk))
    {aurius, [at_fifteen]} = take_schedules(aurius)

    {aurius, blackboard} = Script.run(aurius, blackboard, at_fifteen.steps, at_fifteen.target_guid, 15_000)
    assert blackboard.event_ai.phase == 1
    assert aurius.internal.world == world
  end

  test "Barthilas keeps map 329 copy 73 when the row declares map zero" do
    world = WorldRef.instance(329, 73)
    old_home = {3663.23, -3619.14, 137.984}
    destination = {4068.74, -3535.97, 122.825, 2.47837}

    barthilas =
      mob(10_435, world, {3663.23, -3619.14, 137.984, 5.34071})
      |> active_movement({3800.0, -3600.0, 130.0})
      |> then(
        &%{
          &1
          | internal: %{
              &1.internal
              | in_combat: true,
                threat: %{Guid.from_low_guid(:player, 9) => 25.0}
            }
        }
      )

    steps = [
      %ScriptStep{script_id: 1_043_504, command: :movement, datalong: 0},
      %ScriptStep{script_id: 1_043_504, command: :set_home_position, datalong: 0, position: destination},
      teleport_step(1_043_504, 0, destination)
    ]

    {barthilas, blackboard} = Script.run(barthilas, Blackboard.new(), steps, nil, 500)

    assert barthilas.internal.world == world
    assert barthilas.movement_block.position == destination
    refute barthilas.internal.spawn.position == old_home
    assert barthilas.internal.spawn.position == {4068.74, -3535.97, 122.825}
    assert barthilas.internal.spawn.home_orientation == 2.47837
    assert barthilas.internal.in_combat
    assert map_size(barthilas.internal.threat) == 1
    assert blackboard.navigation.movement_override == :idle
    assert [%Effects.CreatureTeleported{declared_map_id: 0}] = barthilas.internal.events
  end

  test "Spybot and Jesse final-target chains relocate only the receiving owners" do
    world = WorldRef.open(0)
    initiator = mob(7_768, world, {-8400.0, 440.0, 123.0, 0.0})
    spybot = mob(8_856, world, {-8430.7, 442.358, 122.358, 0.856207}) |> active_movement({-8420.0, 445.0, 123.0})
    initiator_position = initiator.movement_block.position

    spybot_steps = [
      %ScriptStep{
        script_id: 4_341,
        command: :movement,
        datalong: 0,
        target_type: :creature_with_guid,
        buddy_guid: spybot.object.guid,
        swap_final?: true
      },
      %{
        teleport_step(4_341, 0, {-8408.25, 451.896, 123.76, 5.52986})
        | target_type: :creature_with_guid,
          buddy_guid: spybot.object.guid,
          swap_final?: true
      }
    ]

    {initiator, _blackboard} = Script.run(initiator, Blackboard.new(), spybot_steps, nil, 1_000)
    forwarded = Enum.flat_map(initiator.internal.events, & &1.steps)
    {spybot, _blackboard} = Script.run(spybot, Blackboard.new(), forwarded, initiator.object.guid, 1_000)

    assert initiator.movement_block.position == initiator_position
    assert spybot.movement_block.position == {-8408.25, 451.896, 123.76, 5.52986}
    assert [%Effects.CreatureTeleported{}] = spybot.internal.events

    actor = mob(1_482, world, {-3670.0, -730.0, 11.0, 0.0})
    jesse = mob(1_445, world, {-3667.39, -733.498, 10.9584, 2.74017})
    actor_position = actor.movement_block.position

    parent = %ScriptStep{
      script_id: 148_201,
      command: :start_script,
      datalong: 144_502,
      dataint: 100,
      target_type: :creature_with_guid,
      buddy_guid: jesse.object.guid,
      swap_final?: true,
      sub_scripts: %{144_502 => jesse_steps()}
    }

    {actor, _blackboard} = Script.run(actor, Blackboard.new(), [parent], nil, 0)
    assert [%Effects.ForwardScriptSteps{steps: [forwarded]}] = actor.internal.events
    {jesse, blackboard} = Script.run(jesse, Blackboard.new(), [forwarded], actor.object.guid, 0)
    {jesse, [at_three]} = take_schedules(jesse)
    {jesse, blackboard} = Script.run(jesse, blackboard, at_three.steps, at_three.target_guid, 3_000)
    {jesse, [at_five]} = take_schedules(jesse)
    {jesse, blackboard} = Script.run(jesse, blackboard, at_five.steps, at_five.target_guid, 5_000)
    {jesse, [at_seven]} = take_schedules(jesse)
    {jesse, _blackboard} = Script.run(jesse, blackboard, at_seven.steps, at_seven.target_guid, 7_000)

    assert actor.movement_block.position == actor_position
    assert jesse.movement_block.position == {-3666.06, -718.628, 9.95469, 0.0}
    assert [%Effects.CreatureTeleported{script_id: 144_502}] = jesse.internal.events
  end

  test "dead creatures remain eligible for the server-controlled unit path" do
    world = WorldRef.instance(329, 90)
    source = mob(1_842, world, {1.0, 2.0, 3.0, 0.0})
    source = %{source | unit: %{source.unit | health: 0}}
    destination = {4.0, 5.0, 6.0, 0.0}

    {teleported, _blackboard} =
      Script.run(source, Blackboard.new(), [teleport_step(184_202, 0, destination)], nil, 1_000)

    assert teleported.movement_block.position == destination
    assert [%Effects.CreatureTeleported{}] = teleported.internal.events
  end

  defp aurius_steps do
    [
      %ScriptStep{script_id: 10_917, delay_ms: 10_000, command: :set_faction, datalong: 250, datalong2: 1},
      %ScriptStep{
        script_id: 10_917,
        delay_ms: 10_000,
        command: :modify_flags,
        datalong: 147,
        datalong2: 3,
        datalong3: 2
      },
      %ScriptStep{script_id: 10_917, delay_ms: 10_000, command: :stand_state, datalong: 0},
      %{teleport_step(10_917, 329, {4032.73, -3366.51, 115.063, 5.42797}) | delay_ms: 11_000},
      %ScriptStep{
        script_id: 10_917,
        delay_ms: 12_000,
        command: :talk,
        texts: [%{text: "The light compels you!", chat_type: :yell, language: 0, emote_id: 0}]
      },
      %ScriptStep{
        script_id: 10_917,
        delay_ms: 12_000,
        command: :move_to,
        datalong: 0,
        position: {4031.0, -3346.89, 115.107, 0.0}
      },
      %ScriptStep{
        script_id: 10_917,
        delay_ms: 12_000,
        command: :set_home_position,
        datalong: 0,
        position: {4033.1, -3349.29, 115.107, 6.0}
      },
      %ScriptStep{script_id: 10_917, delay_ms: 15_000, command: :set_phase, datalong: 1}
    ]
  end

  defp jesse_steps do
    [
      %ScriptStep{
        script_id: 144_502,
        delay_ms: 3_000,
        command: :talk,
        texts: [%{text: "First", chat_type: :say, language: 0, emote_id: 0}]
      },
      %ScriptStep{
        script_id: 144_502,
        delay_ms: 5_000,
        command: :talk,
        texts: [%{text: "Second", chat_type: :say, language: 0, emote_id: 0}]
      },
      %{teleport_step(144_502, 0, {-3666.06, -718.628, 9.95469, 0.0}) | delay_ms: 7_000}
    ]
  end

  defp teleport_step(script_id, declared_map_id, position) do
    %ScriptStep{
      script_id: script_id,
      command: :teleport_to,
      datalong: declared_map_id,
      datalong2: 0,
      position: position
    }
  end

  defp take_schedules(entity) do
    {entity, effects} = Effects.drain(entity)
    {entity, Enum.filter(effects, &is_struct(&1, Effects.ScriptSteps))}
  end

  defp mob(entry, world, {x, y, z, orientation}) do
    guid = Guid.from_low_guid(:mob, entry, rem(entry, 0x00FFFFFF))

    unit = %Unit{
      health: 100,
      max_health: 100,
      level: 60,
      flags: 0,
      npc_flags: 3,
      faction_template: 35,
      stand_state: 1,
      auras: []
    }

    movement_block = %MovementBlock{
      position: {x, y, z, orientation},
      movement_flags: 0,
      walk_speed: 2.5,
      run_speed: 7.0,
      spline_nodes: [],
      duration: 0
    }

    %Mob{
      object: %Object{guid: guid, entry: entry},
      unit: unit,
      movement_block: movement_block,
      internal: %Internal{
        world: world,
        visibility_cell: {world, 0, 0},
        creature: %Creature{},
        spawn: %Spawn{
          unit: unit,
          movement_block: movement_block,
          position: {x, y, z},
          home_orientation: orientation
        },
        blackboard: Blackboard.new(),
        in_combat: false,
        threat: %{}
      }
    }
  end

  defp active_movement(entity, destination) do
    movement_block = %{
      entity.movement_block
      | movement_flags: 0x00400001,
        spline_nodes: [destination],
        spline_flags: 0x100,
        spline_id: 1,
        spline_start_position: entity.movement_block.position |> Tuple.delete_at(3),
        duration: 1_000
    }

    {x, y, z, _orientation} = entity.movement_block.position

    internal = %{
      entity.internal
      | movement_start_time: 0,
        movement_start_position: {x, y, z}
    }

    %{entity | movement_block: movement_block, internal: internal}
  end
end
