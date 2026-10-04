defmodule ThistleTea.Game.Core.InstanceScript.Uldaman do
  @moduledoc """
  The stone guardians of Uldaman, after vmangos `instance_uldaman`.

  Ironaya sleeps as stone behind the Seal of Khaz'Mul. Using the Keystone
  sets the seal grinding open, and when it stands open half a minute later
  she wakes on the nearest intruder.

  Three adventurers kneeling at the Altar of the Keepers wake the four Stone
  Keepers one at a time, each as the last one falls. When all four are dead
  the temple door opens. If an awake keeper gives up its fight, every keeper
  turns back to stone where it stood.

  Three at the Altar of Archaedas wake Archaedas and shut the temple door
  behind them. Every ten seconds of the fight he wakes another of the earthen
  lining the walls, at two thirds health the six Earthen Guardians, and at a
  third the two Vault Warders at his side, while the two warders standing
  outside the chamber fall away. If he gives up the fight the temple door
  opens, and once he is home the earthen he woke turn back to stone. His
  death crumbles the rest, opens the doors and the Ancient Vault, and raises
  the Ancient Treasure (`CreatureScript.Uldaman`).

  vmangos names the two altar events but ships no handler for them;
  `EventScript.Uldaman` starts the encounters here. The creatures that wake
  are the ones this copy saw spawn, and earlier spawns go first.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @ironaya_door 0
  @stone_keepers 1
  @archaedas 2
  @ancient_door 11
  @guardians_awaken 13
  @vault_warders_awaken 14

  @not_started 0
  @in_progress 1
  @fail 2
  @done 3

  @archaedas_entry 2_748
  @stone_keeper 4_857
  @earthen_guardian 7_076
  @earthen_hallshaper 7_077
  @ironaya 7_228
  @earthen_custodian 7_309
  @vault_warder 10_120
  @tracked [
    @archaedas_entry,
    @stone_keeper,
    @earthen_guardian,
    @earthen_hallshaper,
    @ironaya,
    @earthen_custodian,
    @vault_warder
  ]
  @chamber_warders [33_544, 33_549]

  @keystone 124_371
  @seal_of_khazmul 124_372
  @keepers_temple_door 124_367
  @ancient_vault 124_369
  @archaedas_temple_door 141_869

  @stoned 10_255
  @stone_dwarf_awaken 10_254
  @awaken_earthen_dwarf 10_259
  @archaedas_awaken 10_347

  @keeper_faction 470
  @awakened_faction 415
  @say_archaedas_aggro 3_400

  @seal_opens_ms 27_000
  @awaken_visual_ms 1_000
  @awaken_ms 4_000
  @attack_after_ms 500
  @awaken_reach 80

  @unit_flags 46
  @frozen 0x02000300
  @add_flags 1
  @remove_flags 2
  @triggered 0x02
  @restore_on_respawn 0x01

  def broadcast_text_ids, do: [@say_archaedas_aggro]
  def summon_entries, do: []
  def game_object_db_guids, do: []

  def registered_fields,
    do: [@ironaya_door, @stone_keepers, @archaedas, @ancient_door, @guardians_awaken, @vault_warders_awaken]

  def door_entries, do: Enum.map(doors(), &elem(&1, 0))
  def data64(_index), do: nil
  def initial_value(_field), do: @not_started

  def set_data(data, @stone_keepers, @in_progress) do
    if Encounter.done?(data, @stone_keepers),
      do: {:ok, @done, data, []},
      else: {:ok, @in_progress, Map.put(data, @stone_keepers, @in_progress), [schedule(:wake_keeper)]}
  end

  def set_data(data, @archaedas, value), do: archaedas(data, Encounter.value(data, @archaedas), value)

  def set_data(data, field, value) when field in [@guardians_awaken, @vault_warders_awaken] do
    if Encounter.value(data, @archaedas) == @in_progress and Encounter.value(data, field) == @not_started,
      do: {:ok, value, Map.put(data, field, value), [schedule(field)]},
      else: {:ok, Encounter.value(data, field), data, []}
  end

  def set_data(data, field, value) do
    stored = Encounter.settle(data, field, value)
    commit(data, Map.put(data, field, stored), stored, [])
  end

  def game_object_used(data, script_state, @keystone) do
    if Encounter.value(data, @ironaya_door) == @not_started do
      effects = [%Effects.Schedule{key: :seal_opens, delay_ms: @seal_opens_ms}]
      {:ok, Map.put(data, @ironaya_door, @in_progress), script_state, effects}
    else
      {:ok, data, script_state, []}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{event: :spawned, creature_entry: entry} = event) when entry in @tracked do
    role = role(entry, event.db_guid)
    script_state = track(script_state, event.creature_guid, role, event.db_guid)
    {:ok, data, script_state, spawned(data, role, event.creature_guid)}
  end

  def creature_event(data, script_state, %{event: :death, creature_guid: guid} = event) do
    case Map.get(creatures(script_state), guid) do
      %{role: role} -> died(data, put_status(script_state, guid, :dead), role, event)
      nil -> {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, %{event: :evade, creature_guid: guid}) do
    case Map.get(creatures(script_state), guid) do
      %{role: :keeper} -> keepers_give_up(data, script_state)
      %{role: :archaedas} -> transition(data, script_state, @archaedas, @fail)
      _other -> {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, :seal_opens) do
    {:ok, _stored, data, effects} = set_data(data, @ironaya_door, @done)
    {:ok, data, script_state, effects ++ [wake_ironaya()]}
  end

  def timer(data, script_state, :wake_keeper) do
    if Encounter.value(data, @stone_keepers) == @in_progress,
      do: wake_keeper(data, script_state),
      else: {:ok, data, script_state, []}
  end

  def timer(data, script_state, :wake_wall_minion) do
    case {Encounter.value(data, @archaedas), first(script_state, :wall, :frozen)} do
      {@in_progress, guid} when is_integer(guid) ->
        effects = [archaedas_casts(@awaken_earthen_dwarf, guid), awaken_earthen(guid, [])]
        {:ok, data, put_status(script_state, guid, :awake), effects}

      _idle ->
        {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, @guardians_awaken) do
    guardians = all(script_state, :guardian, :frozen)
    script_state = Enum.reduce(guardians, script_state, &put_status(&2, &1, :awake))
    {:ok, data, script_state, Enum.map(guardians, &awaken_earthen(&1, []))}
  end

  def timer(data, script_state, @vault_warders_awaken) do
    furniture = all(script_state, :furniture, :frozen)
    warders = all(script_state, :warder, :frozen)
    script_state = Enum.reduce(furniture, script_state, &put_status(&2, &1, :dead))
    script_state = Enum.reduce(warders, script_state, &put_status(&2, &1, :awake))
    faction = %ScriptStep{command: :set_faction, datalong: @awakened_faction, datalong2: @restore_on_respawn}

    effects =
      Enum.map(furniture, &run(&1, [%ScriptStep{command: :despawn}])) ++
        Enum.map(warders, &awaken_earthen(&1, [faction]))

    {:ok, data, script_state, effects}
  end

  def timer(data, script_state, :reset_chamber) do
    minions =
      Enum.flat_map(
        [:wall, :guardian, :warder, :furniture],
        &(all(script_state, &1, :awake) ++ all(script_state, &1, :dead))
      )

    script_state = Enum.reduce(minions, script_state, &put_status(&2, &1, :frozen))
    {:ok, data, script_state, Enum.map(minions, &run(&1, [respawn(true)]))}
  end

  def timer(data, script_state, :clear_chamber) do
    minions =
      Enum.flat_map([:wall, :guardian, :warder], &(all(script_state, &1, :frozen) ++ all(script_state, &1, :awake)))

    furniture = all(script_state, :furniture, :dead)
    script_state = Enum.reduce(minions, script_state, &put_status(&2, &1, :dead))
    script_state = Enum.reduce(furniture, script_state, &put_status(&2, &1, :frozen))

    effects =
      Enum.map(minions, &run(&1, [%ScriptStep{command: :despawn}])) ++ Enum.map(furniture, &run(&1, [respawn(false)]))

    {:ok, data, script_state, effects}
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp archaedas(data, @done, _value), do: {:ok, @done, data, []}
  defp archaedas(data, @in_progress, @in_progress), do: {:ok, @in_progress, data, [schedule(:wake_wall_minion)]}

  defp archaedas(data, _current, @in_progress) do
    updated =
      Map.merge(data, %{
        @archaedas => @in_progress,
        @ancient_door => @in_progress,
        @guardians_awaken => @not_started,
        @vault_warders_awaken => @not_started
      })

    commit(data, updated, @in_progress, wake_archaedas())
  end

  defp archaedas(data, @in_progress, @fail),
    do: commit(data, Map.merge(data, %{@archaedas => @fail, @ancient_door => @fail}), @fail, [])

  defp archaedas(data, _current, @not_started) do
    updated =
      Map.merge(data, %{
        @archaedas => @not_started,
        @guardians_awaken => @not_started,
        @vault_warders_awaken => @not_started
      })

    commit(data, updated, @not_started, [schedule(:reset_chamber)])
  end

  defp archaedas(data, _current, @done),
    do: commit(data, Map.merge(data, %{@archaedas => @done, @ancient_door => @done}), @done, [schedule(:clear_chamber)])

  defp archaedas(data, current, _value), do: {:ok, current, data, []}

  defp transition(data, script_state, field, value) do
    {:ok, _stored, data, effects} = set_data(data, field, value)
    {:ok, data, script_state, effects}
  end

  defp commit(data, updated, stored, effects),
    do: {:ok, stored, updated, Doors.changed(doors(), data, updated) ++ effects}

  defp spawned(data, :ironaya, guid) do
    if Encounter.done?(data, @ironaya_door),
      do: [run(guid, thaw() ++ [faction(@awakened_faction)])],
      else: [run(guid, freeze())]
  end

  defp spawned(_data, _role, _guid), do: []

  defp died(data, script_state, :keeper, _event) do
    if Encounter.value(data, @stone_keepers) == @in_progress,
      do: {:ok, data, script_state, [schedule(:wake_keeper)]},
      else: {:ok, data, script_state, []}
  end

  defp died(data, script_state, :archaedas, _event), do: transition(data, script_state, @archaedas, @done)
  defp died(data, script_state, _role, _event), do: {:ok, data, script_state, []}

  defp wake_keeper(data, script_state) do
    cond do
      first(script_state, :keeper, :awake) ->
        {:ok, data, script_state, []}

      guid = first(script_state, :keeper, :frozen) ->
        steps = thaw() ++ [faction(@keeper_faction, @restore_on_respawn), attack_nearest(@attack_after_ms)]
        {:ok, data, put_status(script_state, guid, :awake), [run(guid, steps)]}

      all(script_state, :keeper, :dead) != [] ->
        transition(data, script_state, @stone_keepers, @done)

      true ->
        transition(data, script_state, @stone_keepers, @fail)
    end
  end

  defp keepers_give_up(data, script_state) do
    if Encounter.value(data, @stone_keepers) == @in_progress do
      keepers = all(script_state, :keeper, :awake) ++ all(script_state, :keeper, :dead)
      script_state = Enum.reduce(keepers, script_state, &put_status(&2, &1, :frozen))
      {:ok, _stored, data, effects} = set_data(data, @stone_keepers, @fail)
      {:ok, data, script_state, effects ++ Enum.map(keepers, &run(&1, [respawn(true)]))}
    else
      {:ok, data, script_state, []}
    end
  end

  defp wake_ironaya do
    %Effects.RunCreatureScript{
      creature_entry: @ironaya,
      steps: thaw() ++ [faction(@awakened_faction), attack_nearest(@attack_after_ms)]
    }
  end

  defp wake_archaedas do
    [
      %Effects.RunCreatureScript{
        creature_entry: @archaedas_entry,
        steps: [cast_self(@archaedas_awaken) | thaw()] ++ [attack_nearest(@awaken_ms)]
      },
      %Effects.MonsterTalk{creature_entry: @archaedas_entry, broadcast_text_id: @say_archaedas_aggro}
    ]
  end

  defp awaken_earthen(guid, setup) do
    steps =
      [flags(@remove_flags) | setup] ++
        [
          %{cast_self(@stone_dwarf_awaken) | delay_ms: @awaken_visual_ms},
          %ScriptStep{command: :remove_aura, datalong: @stoned, delay_ms: @awaken_ms},
          attack_nearest(@awaken_ms)
        ]

    run(guid, steps)
  end

  defp archaedas_casts(spell_id, guid) do
    %Effects.RunCreatureScript{
      creature_entry: @archaedas_entry,
      steps: [%ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :creature_with_guid, buddy_guid: guid}]
    }
  end

  defp thaw, do: [flags(@remove_flags), %ScriptStep{command: :remove_aura, datalong: @stoned}]
  defp freeze, do: [flags(@add_flags), cast_self(@stoned)]

  defp flags(mode), do: %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: @frozen, datalong3: mode}

  defp faction(faction_id, flags \\ 0), do: %ScriptStep{command: :set_faction, datalong: faction_id, datalong2: flags}

  defp attack_nearest(delay_ms) do
    %ScriptStep{
      command: :attack_start,
      target_type: :nearest_hostile_player,
      target_param1: @awaken_reach,
      delay_ms: delay_ms
    }
  end

  defp cast_self(spell_id),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: @triggered, target_self?: true}

  defp respawn(even_if_alive?),
    do: %ScriptStep{command: :respawn_creature, datalong: if(even_if_alive?, do: 1, else: 0)}

  defp run(guid, steps), do: %Effects.RunCreatureScript{creature_entry: nil, creature_guid: guid, steps: steps}
  defp schedule(key), do: %Effects.Schedule{key: key, delay_ms: 0}

  defp role(@stone_keeper, _db_guid), do: :keeper
  defp role(@ironaya, _db_guid), do: :ironaya
  defp role(@archaedas_entry, _db_guid), do: :archaedas
  defp role(@earthen_guardian, _db_guid), do: :guardian
  defp role(@vault_warder, db_guid) when db_guid in @chamber_warders, do: :warder
  defp role(@vault_warder, _db_guid), do: :furniture
  defp role(_wall_minion, _db_guid), do: :wall

  defp creatures(script_state), do: Map.get(script_state, :creatures, %{})

  defp track(script_state, guid, role, db_guid) do
    creature = %{role: role, status: :frozen, order: db_guid || guid}
    Map.put(script_state, :creatures, Map.put(creatures(script_state), guid, creature))
  end

  defp put_status(script_state, guid, status) do
    Map.put(script_state, :creatures, Map.update!(creatures(script_state), guid, &%{&1 | status: status}))
  end

  defp all(script_state, role, status) do
    script_state
    |> creatures()
    |> Enum.filter(fn {_guid, creature} -> creature.role == role and creature.status == status end)
    |> Enum.sort_by(fn {_guid, creature} -> creature.order end)
    |> Enum.map(&elem(&1, 0))
  end

  defp first(script_state, role, status), do: script_state |> all(role, status) |> List.first()

  defp doors do
    [
      {@seal_of_khazmul, &Encounter.done?(&1, @ironaya_door)},
      {@keepers_temple_door, &Encounter.done?(&1, @stone_keepers)},
      {@ancient_vault, &Encounter.done?(&1, @archaedas)},
      {@archaedas_temple_door, &(Encounter.value(&1, @ancient_door) in [@fail, @done])}
    ]
  end
end
