defmodule ThistleTea.Game.World.System.ScriptedEventTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.ScriptedEvent, as: ScriptedEventSystem
  alias ThistleTea.Game.WorldRef

  setup do
    :sys.replace_state(ScriptedEventSystem, fn _events -> %{} end)

    id = System.unique_integer([:positive, :monotonic])
    source_guid = Guid.from_low_guid(:mob, 7_784, id)
    target_guid = Guid.from_low_guid(:player, id)
    extra_guid = Guid.from_low_guid(:mob, 4_236, id + 1)
    world = %WorldRef{map_id: 0}

    Enum.each([source_guid, target_guid, extra_guid], &Entity.register/1)
    Metadata.put(source_guid, %{alive?: true})
    Metadata.put(target_guid, %{alive?: true})
    Metadata.put(extra_guid, %{alive?: true})
    SpatialHash.update(:mobs, source_guid, world, 0.0, 0.0, 0.0)
    SpatialHash.update(:players, target_guid, world, 10.0, 0.0, 0.0)
    SpatialHash.update(:mobs, extra_guid, world, 5.0, 0.0, 0.0)

    on_exit(fn ->
      Enum.each([source_guid, target_guid, extra_guid], fn guid ->
        Entity.unregister(guid)
        Metadata.delete(guid)
      end)

      SpatialHash.remove(:mobs, source_guid)
      SpatialHash.remove(:players, target_guid)
      SpatialHash.remove(:mobs, extra_guid)
      :sys.replace_state(ScriptedEventSystem, fn _events -> %{} end)
    end)

    {:ok, source_guid: source_guid, target_guid: target_guid, extra_guid: extra_guid, world: world}
  end

  test "escort failure conditions run the configured failure script", context do
    failure = %ScriptStep{command: :fail_quest, datalong: 648}

    start = %ScriptStep{
      command: :start_map_event,
      datalong: 648,
      datalong2: 600,
      dataint3: 1_019,
      dataint4: 64_801,
      failure_condition: %Condition{type: :escort, value1: 1, value2: 80},
      sub_scripts: %{64_801 => [failure]}
    }

    command(context, start)
    Metadata.update(context.source_guid, %{alive?: false})
    evaluate_event()

    assert_receive {:"$gen_cast", {:start_script, [^failure], target_guid}}
    assert target_guid == context.target_guid
    assert :sys.get_state(ScriptedEventSystem) == %{}
  end

  test "map event data can satisfy the success condition", context do
    success = %ScriptStep{command: :quest_explored, datalong: 3382}

    start = %ScriptStep{
      command: :start_map_event,
      datalong: 338_201,
      datalong2: 600,
      dataint: 1_015,
      dataint2: 33_822,
      success_condition: %Condition{
        type: :map_event_data,
        value1: 338_201,
        value2: 0,
        value3: 2,
        value4: 1
      },
      sub_scripts: %{33_822 => [success]}
    }

    command(context, start)
    command(context, %ScriptStep{command: :set_map_event_data, datalong: 338_201, datalong3: 2, datalong4: 1})
    evaluate_event()

    assert_receive {:"$gen_cast", {:start_script, [^success], target_guid}}
    assert target_guid == context.target_guid
  end

  test "condition results expose map event and nearby game object state", context do
    start = %ScriptStep{command: :start_map_event, datalong: 5_713, datalong2: 600}
    command(context, start)

    game_object_guid = Guid.from_low_guid(:game_object, 21_145, System.unique_integer([:positive]))
    SpatialHash.update(:game_objects, game_object_guid, context.world, 12.0, 0.0, 0.0)

    on_exit(fn -> SpatialHash.remove(:game_objects, game_object_guid) end)

    conditions = [
      %Condition{entry: 1, type: :map_event_active, value1: 5_713},
      %Condition{entry: 2, type: :nearby_game_object, value1: 21_145, value2: 30},
      %Condition{entry: 3, type: :nearby_creature, value1: 4_236, value2: 30},
      %Condition{entry: 4, type: :distance_to_target, value1: 10, value2: 0},
      %Condition{entry: 5, type: :distance_to_position, value1: 10, value2: 0, value3: 0, value4: 1}
    ]

    assert ScriptedEventSystem.condition_results(
             context.world,
             context.source_guid,
             context.target_guid,
             conditions
           ) == %{1 => :met, 2 => :met, 3 => :met, 4 => :met, 5 => :met}
  end

  test "condition results preserve exact faction-reaction comparisons", context do
    player_faction = %FactionTemplate{faction: 1, faction_group: 1, friend_group: 1}
    creature_faction = %FactionTemplate{faction: 29}

    Metadata.update(context.source_guid, %{
      faction_template: creature_faction,
      faction_can_have_reputation?: true
    })

    Metadata.update(context.target_guid, %{
      faction_template: player_faction,
      reputation: %{29 => %{rank: :honored, at_war?: false}}
    })

    condition = %Condition{entry: 6, type: :reaction, value1: 4, value2: 1}

    assert ScriptedEventSystem.condition_results(
             context.world,
             context.source_guid,
             context.target_guid,
             [condition]
           ) == %{6 => :met}

    Metadata.update(context.target_guid, %{reputation: %{29 => %{rank: :honored, at_war?: true}}})

    assert ScriptedEventSystem.condition_results(
             context.world,
             context.source_guid,
             context.target_guid,
             [condition]
           ) == %{6 => :unmet}
  end

  test "nearby-player modes distinguish any, hostile, and friendly players", context do
    Metadata.update(context.source_guid, %{
      faction_template: %FactionTemplate{faction: 15, faction_group: 8, enemy_group: 1}
    })

    Metadata.update(context.target_guid, %{
      faction_template: %FactionTemplate{faction: 1, faction_group: 1, friend_group: 1}
    })

    conditions = [
      %Condition{entry: 9, type: :nearby_player, value1: 0, value2: 30},
      %Condition{entry: 10, type: :nearby_player, value1: 1, value2: 30},
      %Condition{entry: 11, type: :nearby_player, value1: 2, value2: 30}
    ]

    assert ScriptedEventSystem.condition_results(
             context.world,
             context.target_guid,
             context.source_guid,
             conditions
           ) == %{9 => :met, 10 => :met, 11 => :unmet}
  end

  test "object-fit conditions evaluate the referenced game-object snapshot", context do
    db_guid = System.unique_integer([:positive, :monotonic])
    game_object_guid = Guid.from_low_guid(:game_object, 21_145, db_guid)

    Metadata.put(game_object_guid, %{db_guid: db_guid, go_spawned?: true, go_state: 0})
    SpatialHash.update(:game_objects, game_object_guid, context.world, 12.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(game_object_guid)
      SpatialHash.remove(:game_objects, game_object_guid)
    end)

    condition = %Condition{
      entry: 7,
      type: :object_fit_condition,
      value1: db_guid,
      value2: 122,
      children: [%Condition{entry: 122, type: :object_spawned}]
    }

    assert ScriptedEventSystem.condition_results(
             context.world,
             context.source_guid,
             context.target_guid,
             [condition]
           ) == %{7 => :met}

    Metadata.update(game_object_guid, %{go_spawned?: false})
    reversed = %{condition | children: [%Condition{entry: 61, type: :object_spawned, reverse?: true}]}

    assert ScriptedEventSystem.condition_results(
             context.world,
             context.source_guid,
             context.target_guid,
             [reversed]
           ) == %{7 => :met}
  end

  test "condition results preserve unavailable world facts as unknown", context do
    condition = %Condition{entry: 8, type: :nearby_creature, value1: 4_236, value2: 30}

    assert %{
             8 =>
               {:unknown,
                [
                  %Reason{
                    entry: 8,
                    type: :nearby_creature,
                    capability: {:missing_fact, :source_or_target, :position}
                  }
                ]}
           } = ScriptedEventSystem.condition_results(context.world, nil, nil, [condition])
  end

  test "target results expose map event source, target, and matching extra targets", context do
    start = %ScriptStep{command: :start_map_event, datalong: 5_944, datalong2: 600}
    add = %ScriptStep{command: :add_map_event_target, datalong: 5_944}
    command(context, start)
    command(%{context | source_guid: context.extra_guid}, add)

    selectors = [
      {:map_event_source, 5_944, 0},
      {:map_event_target, 5_944, 0},
      {:map_event_extra_target, 5_944, Guid.entry(context.extra_guid)}
    ]

    assert ScriptedEventSystem.target_results(context.world, selectors) == %{
             {:map_event_source, 5_944, 0} => context.source_guid,
             {:map_event_target, 5_944, 0} => context.target_guid,
             {:map_event_extra_target, 5_944, Guid.entry(context.extra_guid)} => context.extra_guid
           }
  end

  test "target results resolve creature database guids within one copy", context do
    db_guid = System.unique_integer([:positive, :monotonic])
    other_world = WorldRef.instance(context.world.map_id, 2)
    current_guid = Guid.runtime(:mob, 10_917)
    other_guid = Guid.runtime(:mob, 10_917)

    SpatialHash.update(:mobs, current_guid, context.world, 20.0, 0.0, 0.0)
    SpatialHash.update(:mobs, other_guid, other_world, 20.0, 0.0, 0.0)
    Metadata.put(current_guid, %{db_guid: db_guid})
    Metadata.put(other_guid, %{db_guid: db_guid})

    on_exit(fn ->
      SpatialHash.remove(:mobs, current_guid)
      SpatialHash.remove(:mobs, other_guid)
      Metadata.delete(current_guid)
      Metadata.delete(other_guid)
    end)

    selector = {:creature_with_guid, db_guid, 0}

    assert ScriptedEventSystem.target_results(context.world, [selector]) == %{selector => current_guid}
  end

  test "all-dead target conditions complete multi-creature events", context do
    success = %ScriptStep{command: :quest_explored, datalong: 434}
    dead = %Condition{type: :alive, reverse?: true}

    start = %ScriptStep{
      command: :start_map_event,
      datalong: 434,
      datalong2: 600,
      dataint: 4_340,
      dataint2: 4_340,
      success_condition: %Condition{
        type: :map_event_targets,
        value1: 434,
        value2: 121,
        children: [dead]
      },
      sub_scripts: %{4_340 => [success]}
    }

    add = %ScriptStep{command: :add_map_event_target, datalong: 434}

    command(context, start)
    command(%{context | source_guid: context.extra_guid}, add)
    evaluate_event()
    refute_received {:"$gen_cast", {:start_script, [^success], _target_guid}}

    Metadata.update(context.extra_guid, %{alive?: false})
    evaluate_event()

    assert_receive {:"$gen_cast", {:start_script, [^success], target_guid}}
    assert target_guid == context.target_guid
  end

  test "map event notifications reach only selected creature targets", context do
    start = %ScriptStep{command: :start_map_event, datalong: 5862, datalong2: 600}
    add = %ScriptStep{command: :add_map_event_target, datalong: 5862}

    command(context, start)
    command(%{context | source_guid: context.extra_guid}, add)
    command(context, %ScriptStep{command: :send_map_event, datalong: 5862, datalong2: 7, datalong3: 0})

    assert_receive {:"$gen_cast", {:script_event, 5862, 7, nil}}
    refute_receive {:"$gen_cast", {:script_event, 5862, 7, nil}}

    command(context, %ScriptStep{command: :send_map_event, datalong: 5862, datalong2: 8, datalong3: 1})

    assert_receive {:"$gen_cast", {:script_event, 5862, 8, nil}}
    refute_receive {:"$gen_cast", {:script_event, 5862, 8, nil}}
  end

  test "map event definitions can be edited while active", context do
    success = %ScriptStep{command: :quest_explored, datalong: 434}
    condition = %Condition{type: :map_event_data, value1: 434, value2: 0, value3: 0}

    command(context, %ScriptStep{command: :start_map_event, datalong: 434, datalong2: 600})

    command(
      context,
      %ScriptStep{
        command: :edit_map_event,
        datalong: 434,
        dataint: 4_340,
        dataint2: 4_341,
        dataint3: -1,
        dataint4: -1,
        success_condition: condition,
        sub_scripts: %{4_341 => [success]}
      }
    )

    evaluate_event()

    assert_receive {:"$gen_cast", {:start_script, [^success], target_guid}}
    assert target_guid == context.target_guid
  end

  test "start script for all filters nearby objects by type and entry", context do
    sub_step = %ScriptStep{command: :stand_state, datalong: 0}

    command(
      context,
      %ScriptStep{
        command: :start_script_for_all,
        datalong: 99,
        datalong2: 2,
        datalong3: 4_236,
        datalong4: 20,
        sub_scripts: %{99 => [sub_step]}
      }
    )

    assert_receive {:"$gen_cast", {:start_script, [^sub_step], target_guid}}
    assert target_guid == context.target_guid
    refute_receive {:"$gen_cast", {:start_script, [^sub_step], _target_guid}}
  end

  defp command(context, step) do
    context.world
    |> Effects.scripted_event_command(context.source_guid, context.target_guid, step)
    |> ScriptedEventSystem.command()

    :sys.get_state(ScriptedEventSystem)
    :ok
  end

  defp evaluate_event do
    [{key, event}] = Map.to_list(:sys.get_state(ScriptedEventSystem))
    send(ScriptedEventSystem, {:evaluate, key, event.token})
    :sys.get_state(ScriptedEventSystem)
    :ok
  end
end
