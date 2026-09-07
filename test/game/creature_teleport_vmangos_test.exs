defmodule ThistleTea.Game.CreatureTeleportVmangosTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InstanceSpawn
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  test "pins the complete imported command-6 inventory" do
    assert teleport_rows("creature_ai_scripts") == [
             row({184_202, 0, 0, 0, 0, 0, 0, 0, 0}, {2942.58, -1390.09, 167.421, 4.2586})
           ]

    assert teleport_rows("creature_movement_scripts") == [
             row({144_507, 1, 0, 0, 0, 0, 0, 0, 0}, {-3660.6, -717.77, 28.156, 3.05292}),
             row({144_611, 0, 0, 0, 0, 0, 0, 0, 0}, {-3628.43, -719.022, 10.8226, 0.0}),
             row({1_043_504, 1, 2, 0, 0, 0, 0, 0, 0}, {4068.74, -3535.97, 122.825, 2.47837})
           ]

    assert teleport_rows("generic_scripts") == [
             row({4_341, 1, 1, 0, 0, 11, 45_707, 0, 2}, {-8408.25, 451.896, 123.76, 5.52986}),
             row({10_917, 11, 0, 329, 0, 0, 0, 0, 0}, {4032.73, -3366.51, 115.063, 5.42797}),
             row({144_502, 7, 0, 0, 0, 0, 0, 0, 0}, {-3666.06, -718.628, 9.95469, 0.0})
           ]

    assert teleport_rows("quest_start_scripts") == []
    assert teleport_rows("quest_end_scripts") == []
  end

  test "pins final-target routing and creature same-world regressions" do
    assert rows(
             "SELECT id, command, datalong, target_type, target_param1, data_flags FROM creature_ai_scripts WHERE id = 1044001 AND command = 39"
           ) == [[1_044_001, 39, 10_917, 11, 53_297, 2]]

    assert rows(
             "SELECT id, command, datalong, target_type, target_param1, data_flags FROM creature_movement_scripts WHERE id = 148201 AND command = 39"
           ) == [[148_201, 39, 144_502, 11, 9_566, 2]]

    assert rows(
             "SELECT id, command, target_type, target_param1, data_flags FROM generic_scripts WHERE id = 4341 AND command = 6"
           ) == [[4_341, 6, 11, 45_707, 2]]

    assert rows("SELECT guid, id, map FROM creature WHERE guid IN (45707, 53297, 9566) ORDER BY guid") == [
             [9_566, 1_445, 0],
             [45_707, 8_856, 0],
             [53_297, 10_917, 329]
           ]

    assert rows("SELECT guid, id, map FROM creature WHERE id = 10435") == [[54_237, 10_435, 329]]
    assert rows("SELECT datalong FROM creature_movement_scripts WHERE id = 1043504 AND command = 6") == [[0]]
  end

  test "loaded Baron aggro resolves Aurius inside the current copy" do
    world = WorldRef.instance(329, System.unique_integer([:positive, :monotonic]))
    player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    baron = 54_241 |> mob_fixture() |> InstanceSpawn.materialize(world)
    aurius = 53_297 |> mob_fixture() |> InstanceSpawn.materialize(world)

    Enum.each([baron, aurius], fn mob ->
      World.update_position(mob)
      Metadata.put(mob.object.guid, Mob.visibility_metadata(mob))
    end)

    on_exit(fn ->
      Enum.each([baron, aurius], fn mob ->
        SpatialHash.remove(:mobs, mob.object.guid)
        Metadata.delete(mob.object.guid)
      end)
    end)

    context = AIEnvironment.context(baron, 1_000)
    selector = {:creature_with_guid, 53_297, 0}
    assert context.script_targets[selector] == aurius.object.guid

    {baron, _blackboard} = EventAI.enter_combat(baron, Blackboard.new(), player_guid, 1_000, context)

    assert Enum.any?(baron.internal.events, fn
             %Effects.ForwardScriptSteps{target_guid: target_guid} -> target_guid == aurius.object.guid
             _effect -> false
           end)
  end

  defp teleport_rows(table) do
    table
    |> then(
      &rows(
        "SELECT id, delay, priority, datalong, datalong2, target_type, target_param1, target_param2, data_flags, x, y, z, o FROM #{&1} WHERE command = 6 ORDER BY id, delay, priority"
      )
    )
    |> Enum.map(fn [id, delay, priority, map_id, options, target_type, target_param1, target_param2, flags, x, y, z, o] ->
      row({id, delay, priority, map_id, options, target_type, target_param1, target_param2, flags}, {x, y, z, o})
    end)
  end

  defp row({id, delay, priority, map_id, options, target_type, target_param1, target_param2, flags}, position) do
    %{
      id: id,
      delay: delay,
      priority: priority,
      declared_map_id: map_id,
      options: options,
      target_type: target_type,
      target_param1: target_param1,
      target_param2: target_param2,
      data_flags: flags,
      position: rounded_position(position)
    }
  end

  defp rounded_position(position) do
    position
    |> Tuple.to_list()
    |> Enum.map(&Float.round(&1 / 1, 5))
    |> List.to_tuple()
  end

  defp rows(query), do: SQL.query!(Repo, query, []).rows

  defp mob_fixture(guid) do
    creature =
      Mangos.Creature.query_guids([guid], [])
      |> Repo.one!()
      |> Repo.preload([:creature_template, :creature_movement])

    events = Mangos.CreatureAiEvent.query(creature.id) |> Repo.all()
    script_ids = Enum.flat_map(events, &Mangos.CreatureAiEvent.action_script_ids/1)
    scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, script_ids)
    conditions = ConditionLoader.load_by_ids(Enum.map(events, & &1.condition_id))

    ai_events =
      Enum.map(events, fn row ->
        event = AIEvent.build(row, scripts)
        %{event | condition: Map.get(conditions, event.condition_id)}
      end)

    Mob.build(%{creature | ai_events: ai_events})
  end
end
