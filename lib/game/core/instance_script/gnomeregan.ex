defmodule ThistleTea.Game.Core.InstanceScript.Gnomeregan do
  @moduledoc """
  Grubbis's cave-ins and Mekgineer Thermaplugg's bomb faces, after vmangos
  `instance_gnomeregan`.

  Blastmaster Emi Shortfuse (`CreatureScript.Gnomeregan`) opens each cave-in
  as she leads the party to it and plants explosive charges along the way,
  two for the southern tunnel and two for the northern. When a tunnel's
  troggs are beaten back she blows its charges and the rubble falls in again.
  Grubbis's death ends the event and brings the red rockets back for an hour.
  Her death fails it: the planted charges vanish and both cave-ins close.

  Thermaplugg locks the door to the final chamber while he fights and opens
  it again when he dies or gives up. The fight opens the third of the six
  gnome faces around his room, and each bomb he activates opens a random one.
  Every open face drops a walking bomb into the room every ten to twenty-five
  seconds while fewer than six are about, and the button under a face closes
  it. When he gives up, his bombs vanish and the faces close.

  Unlike vmangos, a walking bomb walks to Thermaplugg once it lands instead of
  following him.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @grubbis_field 0
  @thermaplugg_field 1
  @charge_field 2
  @south_cave_in_field 3
  @north_cave_in_field 4
  @face_fields 10..15

  @in_progress 1
  @failed 2
  @done 3
  @detonate 5

  @emi 7_998
  @grubbis 7_361
  @thermaplugg 7_800
  @walking_bomb 7_915

  @south_cave_in 146_086
  @north_cave_in 146_085
  @final_chamber 142_207
  @faces [142_211, 142_210, 142_209, 142_208, 142_213, 142_212]
  @buttons [142_214, 142_215, 142_216, 142_217, 142_218, 142_219]
  @opening_face 2

  @charges %{1 => 3_997_159, 2 => 3_997_160, 3 => 3_997_157, 4 => 3_997_158}
  @red_rockets [283, 284, 285]
  @placed_ms 3_600_000

  @thermaplugg_spawn {-531.324, 670.159, -325.185}
  @face_spots [
    {-561.236, 709.881},
    {-518.904, 718.472},
    {-485.723, 690.871},
    {-486.665, 647.652},
    {-521.022, 621.549},
    {-562.961, 632.162}
  ]
  @bomb_drop_z -316.2625
  @max_bombs 6
  @first_bomb_ms 3_000
  @bomb_min_ms 10_000
  @bomb_max_ms 25_000
  @fall_ms 800
  @thermaplugg_reach 100
  @pathfind 0x1
  @corpse_despawn 5

  def broadcast_text_ids, do: []
  def summon_entries, do: [@walking_bomb]
  def game_object_db_guids, do: Map.values(@charges)

  def registered_fields,
    do: [@grubbis_field, @thermaplugg_field, @charge_field, @south_cave_in_field, @north_cave_in_field | face_fields()]

  def door_entries, do: [@south_cave_in, @north_cave_in]
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, @grubbis_field, value) do
    previous = Encounter.value(data, @grubbis_field)
    stored = Encounter.settle(data, @grubbis_field, value)
    data = Map.put(data, @grubbis_field, stored)

    case if(stored == previous, do: :unchanged, else: stored) do
      @failed -> {:ok, stored, data, []} |> also(@south_cave_in_field, 0) |> also(@north_cave_in_field, 0) |> detonate()
      @done -> {:ok, stored, data, Enum.map(@red_rockets, &respawn/1)}
      _other -> {:ok, stored, data, []}
    end
  end

  def set_data(data, @charge_field, value) when is_map_key(@charges, value),
    do: {:ok, value, Map.put(data, @charge_field, value), [respawn(Map.fetch!(@charges, value))]}

  def set_data(data, @charge_field, @detonate),
    do: detonate({:ok, @detonate, Map.put(data, @charge_field, @detonate), []})

  def set_data(data, @charge_field, value), do: {:ok, value, Map.put(data, @charge_field, value), []}

  def set_data(data, field, value) when field in [@south_cave_in_field, @north_cave_in_field],
    do: Doors.put(cave_ins(), data, field, value)

  def set_data(data, field, value) when field in @face_fields do
    index = field - @face_fields.first
    active? = value != 0

    effects =
      cond do
        active? == face_active?(data, index) -> []
        active? -> [face(index, :open), %Effects.Schedule{key: {:bomb, index}, delay_ms: @first_bomb_ms}]
        true -> [face(index, :reset), %Effects.CancelSchedules{keys: [{:bomb, index}]}]
      end

    {:ok, value, Map.put(data, field, value), effects}
  end

  def set_data(data, @thermaplugg_field, value) do
    previous = Encounter.value(data, @thermaplugg_field)
    stored = Encounter.settle(data, @thermaplugg_field, value)
    data = Map.put(data, @thermaplugg_field, stored)

    case if(stored == previous, do: :unchanged, else: stored) do
      @in_progress ->
        {:ok, stored, data, [door(:lock)]} |> also(face_field(@opening_face), 1)

      ending when ending in [@failed, @done] ->
        Enum.reduce(face_fields(), {:ok, stored, data, [door(:unlock)]}, &also(&2, &1, 0))

      _other ->
        {:ok, stored, data, []}
    end
  end

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    {:ok, stored, Map.put(data, field, stored), []}
  end

  def game_object_used(data, script_state, entry) do
    case Enum.find_index(@buttons, &(&1 == entry)) do
      nil ->
        {:ok, data, script_state, []}

      index ->
        {:ok, _stored, data, effects} = set_data(data, face_field(index), 0)
        {:ok, data, script_state, effects}
    end
  end

  def game_object_spawned(data, _script_state, @final_chamber) do
    case Encounter.value(data, @thermaplugg_field) do
      @in_progress -> {:ok, [door(:lock)]}
      ending when ending in [@failed, @done] -> {:ok, [door(:unlock)]}
      _not_started -> {:ok, []}
    end
  end

  def game_object_spawned(data, _script_state, entry) when entry in [@south_cave_in, @north_cave_in],
    do: {:ok, Doors.spawned(cave_ins(), data, %{}, entry)}

  def game_object_spawned(data, _script_state, entry) do
    case Enum.find_index(@faces, &(&1 == entry)) do
      nil -> {:ok, []}
      index -> if face_active?(data, index), do: {:ok, [face(index, :open)]}, else: {:ok, []}
    end
  end

  def creature_event(data, script_state, %{creature_entry: @emi, event: :death}),
    do: event_data(data, script_state, @grubbis_field, @failed)

  def creature_event(data, script_state, %{creature_entry: @grubbis, event: :death}),
    do: event_data(data, script_state, @grubbis_field, @done)

  def creature_event(data, script_state, %{creature_entry: @thermaplugg, event: :aggro}),
    do: event_data(data, script_state, @thermaplugg_field, @in_progress)

  def creature_event(data, script_state, %{creature_entry: @thermaplugg, event: :death}),
    do: event_data(data, script_state, @thermaplugg_field, @done)

  def creature_event(data, script_state, %{creature_entry: @thermaplugg, event: :evade}) do
    {:ok, data, script_state, effects} = event_data(data, script_state, @thermaplugg_field, @failed)
    clear = %Effects.RunCreatureScript{creature_entry: @walking_bomb, steps: [%ScriptStep{command: :despawn}]}
    {:ok, data, Map.put(script_state, :bombs, 0), effects ++ [clear]}
  end

  def creature_event(data, script_state, %{creature_entry: @walking_bomb, event: :death}),
    do: {:ok, data, Map.update(script_state, :bombs, 0, &max(&1 - 1, 0)), []}

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, {:bomb, index}) do
    if face_active?(data, index) and Encounter.value(data, @thermaplugg_field) == @in_progress do
      next = %Effects.Schedule{key: {:bomb, index}, delay_ms: @bomb_min_ms, max_delay_ms: @bomb_max_ms}
      bombs = Map.get(script_state, :bombs, 0)

      if bombs < @max_bombs,
        do: {:ok, data, Map.put(script_state, :bombs, bombs + 1), [drop_bomb(index), next]},
        else: {:ok, data, script_state, [next]}
    else
      {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp event_data(data, script_state, field, value) do
    {:ok, _stored, data, effects} = set_data(data, field, value)
    {:ok, data, script_state, effects}
  end

  defp also({:ok, stored, data, effects}, field, value) do
    {:ok, _stored, data, more} = set_data(data, field, value)
    {:ok, stored, data, effects ++ more}
  end

  defp detonate({:ok, stored, data, effects}),
    do: {:ok, stored, data, effects ++ Enum.map(Map.values(@charges), &%Effects.SuspendGameObject{db_guid: &1})}

  defp drop_bomb(index) do
    {sx, sy, sz} = @thermaplugg_spawn
    {fx, fy} = Enum.at(@face_spots, index)
    {bx, by} = {0.35 * sx + 0.65 * fx, 0.35 * sy + 0.65 * fy}

    %Effects.SummonCreature{
      entry: @walking_bomb,
      position: {bx, by, @bomb_drop_z, 0.0},
      despawn_delay_ms: 0,
      despawn_type: @corpse_despawn,
      steps: [
        %ScriptStep{
          command: :move_to,
          datalong2: @fall_ms,
          position: {0.2 * sx + 0.8 * bx, 0.2 * sy + 0.8 * by, sz - 2.0, 0.0}
        },
        %ScriptStep{
          command: :move_to,
          delay_ms: @fall_ms,
          datalong: 2,
          datalong3: @pathfind,
          target_type: :nearest_creature_with_entry,
          target_param1: @thermaplugg,
          target_param2: @thermaplugg_reach,
          position: {0.0, 0.0, 0.0, -1.0}
        }
      ]
    }
  end

  defp cave_ins do
    [
      {@south_cave_in, &(Map.get(&1, @south_cave_in_field, 0) != 0)},
      {@north_cave_in, &(Map.get(&1, @north_cave_in_field, 0) != 0)}
    ]
  end

  defp face_fields, do: Enum.to_list(@face_fields)
  defp face_field(index), do: @face_fields.first + index
  defp face_active?(data, index), do: Map.get(data, face_field(index), 0) != 0
  defp face(index, action), do: %Effects.OperateGameObject{entry: Enum.at(@faces, index), action: action}
  defp door(action), do: %Effects.OperateGameObject{entry: @final_chamber, action: action}
  defp respawn(db_guid), do: %Effects.RespawnGameObject{db_guid: db_guid, duration_ms: @placed_ms}
end
