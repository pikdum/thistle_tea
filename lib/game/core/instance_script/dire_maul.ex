defmodule ThistleTea.Game.Core.InstanceScript.DireMaul do
  @moduledoc """
  The wings of Dire Maul, after vmangos `instance_dire_maul`.

  West: five crystal generators feed the force field around Immol'thar, each
  guarded by the Mana Remnants and Arcane Aberrations around it. Killing the
  last guard of a generator shuts it down, and when all five are dark the
  field and the vortex above it fall. Immol'thar can be targeted, and the
  Highborne Summoners in his hall turn on him. His death makes Prince
  Tortheldrin attackable.

  East: Zevrim Thornhoof's death frees Old Ironbark, whose door then opens
  for the party. Alzzin the Wildshaper breaks through the crumbling wall
  when hard pressed, and his death clears the corrupted vine and raises the
  Felvine Shards.

  North: Guards Fengus, Slip'kik, and Mol'dar, Stomper Kreeg, Captain
  Kromcrush, and Cho'Rush the Observer count toward King Gordok's tribute.
  The king's death calls Mizzle the Crafty and makes Cho'Rush stand down.
  Once Mizzle shows the new king the tribute, the chest appears, and its
  loot is set by how many of those six were still alive.

  vmangos counts the tribute guards from their death scripts and its own
  death hook, so four of them count twice; here each guard counts once.
  The generators are matched to the guards spawned within 20 yards of them,
  where vmangos sorts whoever stands there at the first guard's death. The
  tribute chest and the shards stay up for an hour, where vmangos gives them
  a minute.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @crystals 1
  @immol_thar 2
  @tendris_aggro 3
  @zevrim 4
  @ironbark 5
  @tribute 6
  @broken_trap 7
  @ogre_suit 8
  @chorush_equipment 9
  @moldar 10
  @alzzin 11
  @tannin_looted 13
  @final_guards_alive 15

  @in_progress 1
  @done 3
  @special 4

  @zevrim_entry 11_490
  @alzzin_entry 11_492
  @immol_thar_entry 11_496
  @tortheldrin 11_486
  @highborne_summoner 11_466
  @king_gordok 11_501
  @chorush 14_324
  @mizzle 14_353
  @moldar_entry 14_326
  @tribute_guards [14_321, 14_322, 14_323, @moldar_entry, 14_325, @chorush]

  @force_field 179_503
  @magic_vortex 179_506
  @crumble_wall 177_220
  @corrupt_vine 179_502
  @tribute_chest 396_409
  @felvine_shards [44_726, 44_727, 44_728, 44_729, 44_730]

  @generators %{
    177_259 => [84_210, 84_211, 84_212, 84_213, 84_214, 84_215, 84_216, 84_218],
    177_257 => [84_223, 84_224, 84_225, 84_227, 84_230, 84_231, 84_234, 84_235],
    177_258 => [84_219, 84_220, 84_221, 84_222, 84_239, 84_240, 84_241, 84_242],
    179_504 => [84_245, 84_246, 84_247, 84_257, 84_258, 84_259, 84_260, 84_261],
    179_505 => [84_262, 84_264, 84_265, 84_266, 84_267]
  }
  @hall_summoners [56_952, 300_172, 300_851, 300_852, 300_853, 300_854, 300_855, 300_856, 300_857]
  @immol_thar_hall {-38.08, 812.44, -29.45}
  @hall_reach 100

  @say_free_immol_thar 9_364
  @say_king_dead 9_472
  @say_immol_thar_dead 9_407

  @imprisoned 0x02000002
  @freed 0x02000202
  @unit_flags 46
  @immune_to_players 0x100
  @remove_flags 2
  @restore_on_respawn 0x01
  @friendly 35
  @hostile 14
  @summoner_faction 100
  @sit 1
  @attack_after_ms 1_000
  @king_dead_say_ms 5_000
  @chest_up_ms 3_600_000
  @dead_despawn 7
  @mizzle_post {693.44, 480.806, 28.175, 0.02757}

  def broadcast_text_ids, do: [@say_free_immol_thar, @say_king_dead, @say_immol_thar_dead]
  def summon_entries, do: [@mizzle]
  def game_object_db_guids, do: [@tribute_chest | @felvine_shards]

  def registered_fields do
    [
      @crystals,
      @immol_thar,
      @tendris_aggro,
      @zevrim,
      @ironbark,
      @tribute,
      @broken_trap,
      @ogre_suit,
      @chorush_equipment,
      @moldar,
      @alzzin,
      @tannin_looted,
      @final_guards_alive
    ]
  end

  def door_entries, do: Enum.map(doors(), &elem(&1, 0)) ++ Map.keys(@generators)
  def data64(_index), do: nil
  def initial_value(@final_guards_alive), do: length(@tribute_guards)
  def initial_value(_field), do: 0

  def generator_guards, do: @generators

  def set_data(data, @tribute, @special),
    do: commit(data, Map.put(data, @tribute, tribute_progress(data)), tribute_progress(data), [])

  def set_data(data, @tribute, @done) do
    if Encounter.done?(data, @tribute),
      do: {:ok, @done, data, []},
      else: commit(data, Map.put(data, @tribute, @done), @done, [raise_object(@tribute_chest)])
  end

  def set_data(data, @alzzin, @done) do
    if Encounter.done?(data, @alzzin),
      do: {:ok, @done, data, []},
      else: commit(data, Map.put(data, @alzzin, @done), @done, Enum.map(@felvine_shards, &raise_object/1))
  end

  def set_data(data, @alzzin, @special) do
    stored = Encounter.settle(data, @alzzin, @special)
    commit(data, Map.put(data, @alzzin, stored), stored, [])
  end

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    commit(data, Map.put(data, field, stored), stored, [])
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(_data, script_state, entry) when is_map_key(@generators, entry) do
    if MapSet.member?(dark_generators(script_state), entry),
      do: {:ok, [%Effects.OperateGameObject{entry: entry, action: :open}]},
      else: {:ok, []}
  end

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{event: :spawned, creature_entry: @immol_thar_entry}) do
    if Encounter.done?(data, @crystals),
      do: {:ok, data, script_state, []},
      else: {:ok, data, script_state, [flags(@immol_thar_entry, @imprisoned, :add)]}
  end

  def creature_event(data, script_state, %{event: :spawned, creature_entry: @tortheldrin}) do
    if Encounter.done?(data, @immol_thar),
      do: {:ok, data, script_state, [unlock_tortheldrin()]},
      else: {:ok, data, script_state, []}
  end

  def creature_event(data, script_state, %{event: :spawned, creature_entry: @chorush}) do
    if Encounter.done?(data, @tribute),
      do: {:ok, data, script_state, [creature(@chorush, [faction(@friendly), stand(@sit)])]},
      else: {:ok, data, script_state, []}
  end

  def creature_event(data, script_state, %{event: :spawned, creature_entry: @highborne_summoner} = event) do
    if event.db_guid in @hall_summoners,
      do: {:ok, data, Map.update(script_state, :summoners, [event.creature_guid], &(&1 ++ [event.creature_guid])), []},
      else: {:ok, data, script_state, []}
  end

  def creature_event(data, script_state, %{event: :death, creature_entry: @highborne_summoner} = event),
    do: {:ok, data, Map.update(script_state, :summoners, [], &List.delete(&1, event.creature_guid)), []}

  def creature_event(data, script_state, %{event: :death, db_guid: db_guid} = event) when is_integer(db_guid) do
    case Enum.find(@generators, fn {_entry, guards} -> db_guid in guards end) do
      {entry, _guards} -> guard_fell(data, script_state, entry, db_guid)
      nil -> died(data, script_state, event)
    end
  end

  def creature_event(data, script_state, %{event: :death} = event), do: died(data, script_state, event)
  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp guard_fell(data, script_state, entry, db_guid) do
    fallen = MapSet.put(Map.get(script_state, :fallen, MapSet.new()), db_guid)
    script_state = Map.put(script_state, :fallen, fallen)

    cond do
      Encounter.done?(data, @crystals) or not Enum.all?(@generators[entry], &MapSet.member?(fallen, &1)) ->
        {:ok, data, script_state, []}

      MapSet.size(dark_generators(script_state)) == map_size(@generators) ->
        {:ok, _stored, data, effects} = set_data(data, @crystals, @done)
        {:ok, data, script_state, [shut_down(entry) | effects] ++ free_immol_thar(script_state)}

      true ->
        {:ok, data, script_state, [shut_down(entry)]}
    end
  end

  defp died(data, script_state, %{creature_entry: @immol_thar_entry}) do
    {:ok, _stored, data, effects} = set_data(data, @immol_thar, @done)

    {:ok, data, script_state, effects ++ [talk(@tortheldrin, @say_immol_thar_dead), unlock_tortheldrin()]}
  end

  defp died(data, script_state, %{creature_entry: @zevrim_entry}), do: transition(data, script_state, @zevrim, @done)
  defp died(data, script_state, %{creature_entry: @alzzin_entry}), do: transition(data, script_state, @alzzin, @done)

  defp died(data, script_state, %{creature_entry: @king_gordok}) do
    mizzle = %Effects.SummonCreature{
      entry: @mizzle,
      position: @mizzle_post,
      despawn_type: @dead_despawn,
      despawn_delay_ms: 0
    }

    stand_down =
      creature(@chorush, [
        faction(@friendly),
        %ScriptStep{command: :talk, dataint: @say_king_dead, delay_ms: @king_dead_say_ms}
      ])

    effects = if Map.get(script_state, :chorush_dead?, false), do: [mizzle], else: [mizzle, stand_down]
    {:ok, data, script_state, effects}
  end

  defp died(data, script_state, %{creature_entry: entry}) when entry in @tribute_guards do
    script_state = if entry == @chorush, do: Map.put(script_state, :chorush_dead?, true), else: script_state
    data = if entry == @moldar_entry, do: Map.put(data, @moldar, @done), else: data

    if Encounter.done?(data, @tribute) do
      {:ok, data, script_state, []}
    else
      alive = max(Map.get(data, @final_guards_alive, initial_value(@final_guards_alive)) - 1, 0)
      {:ok, Map.put(data, @final_guards_alive, alive), script_state, []}
    end
  end

  defp died(data, script_state, _event), do: {:ok, data, script_state, []}

  defp free_immol_thar(script_state) do
    turn =
      %Effects.RunCreatureScript{
        creature_entry: @highborne_summoner,
        within: {@immol_thar_hall, @hall_reach},
        steps: [
          %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: @freed, datalong3: @remove_flags},
          %ScriptStep{command: :set_faction, datalong: @summoner_faction, datalong2: @restore_on_respawn},
          %ScriptStep{
            command: :attack_start,
            target_type: :nearest_creature_with_entry,
            target_param1: @immol_thar_entry,
            target_param2: @hall_reach,
            delay_ms: @attack_after_ms
          }
        ]
      }

    yell =
      case Map.get(script_state, :summoners, []) do
        [first | _] ->
          [%Effects.MonsterTalk{creature_entry: nil, creature_guid: first, broadcast_text_id: @say_free_immol_thar}]

        [] ->
          []
      end

    [flags(@immol_thar_entry, @freed, :remove), turn | yell]
  end

  defp unlock_tortheldrin do
    creature(@tortheldrin, [
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_flags,
        datalong2: @immune_to_players,
        datalong3: @remove_flags
      },
      faction(@hostile)
    ])
  end

  defp dark_generators(script_state) do
    fallen = Map.get(script_state, :fallen, MapSet.new())

    for {entry, guards} <- @generators, Enum.all?(guards, &MapSet.member?(fallen, &1)), into: MapSet.new(), do: entry
  end

  defp tribute_progress(data), do: if(Encounter.done?(data, @tribute), do: @done, else: @in_progress)

  defp transition(data, script_state, field, value) do
    {:ok, _stored, data, effects} = set_data(data, field, value)
    {:ok, data, script_state, effects}
  end

  defp commit(data, updated, stored, effects),
    do: {:ok, stored, updated, Doors.changed(doors(), data, updated) ++ effects}

  defp doors do
    [
      {@force_field, &Encounter.done?(&1, @crystals)},
      {@magic_vortex, &Encounter.done?(&1, @crystals)},
      {@crumble_wall, &(Encounter.value(&1, @alzzin) in [@special, @done])},
      {@corrupt_vine, &Encounter.done?(&1, @alzzin)}
    ]
  end

  defp shut_down(entry), do: %Effects.OperateGameObject{entry: entry, action: :open}
  defp raise_object(db_guid), do: %Effects.RespawnGameObject{db_guid: db_guid, duration_ms: @chest_up_ms}
  defp flags(entry, flags, mode), do: %Effects.ModifyCreatureUnitFlags{creature_entry: entry, flags: flags, mode: mode}
  defp creature(entry, steps), do: %Effects.RunCreatureScript{creature_entry: entry, steps: steps}
  defp talk(entry, text_id), do: %Effects.MonsterTalk{creature_entry: entry, broadcast_text_id: text_id}
  defp stand(state), do: %ScriptStep{command: :stand_state, datalong: state}

  defp faction(faction_id), do: %ScriptStep{command: :set_faction, datalong: faction_id, datalong2: @restore_on_respawn}
end
