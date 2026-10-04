defmodule ThistleTea.Game.Core.AI.CreatureScript.StaveOfTheAncients do
  @moduledoc """
  vmangos `npc_artorius`, `npc_klinfran`, `npc_solenor`,
  `npc_simone_the_inconspicuous`, `npc_simone_seductress`,
  `npc_precious_the_devourer`, and `npc_the_cleaner`: the four demons a
  hunter unmasks for Stave of the Ancients (7636).

  A hunter on the quest calls out Artorius the Amiable in Winterspring,
  Franklin the Friendly in the Burning Steppes, Nelson the Nice in Silithus,
  or Simone the Inconspicuous in Un'Goro. The demon stops where it stands,
  gestures, and ten seconds later takes its true form there: Artorius the
  Doombringer, Klinfran the Crazed, Solenor the Slayer, or Simone the
  Seductress, whose pet Precious becomes Precious the Devourer at the same
  moment. Each carries one of the quest's four pieces, and each answers one
  of the hunter's stings: Serpent Sting poisons Artorius, Scorpid Sting
  quells Klinfran's frenzy, Wing Clip roots Solenor and Frost Trap snuffs
  his Soul Flame, and Viper Sting silences Simone.

  The test is the hunter's alone. A demon pulled by anyone else, or with a
  second foe on its threat list, the hunter's own pet included, calls The
  Cleaner down on the meddlers and vanishes for fifteen minutes. Simone and
  Precious stand or fall back together, and either one's crowd banishes
  both. A demon left alone for twenty minutes slips away without the
  Cleaner. vmangos counts those minutes from the unmasking; here a fight
  restarts them, since EventAI scripts stop when their creature enters
  combat.

  An unmasked demon keeps its amiable entry's events, so each phase gates
  its own: the amiable form, the unmasking, the demon, and the demon past
  its patience. A respawn brings the amiable form back on its path.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @artorius 14_531
  @franklin 14_529
  @nelson 14_536
  @simone 14_527
  @precious 14_528
  @devourer 14_538
  @seductress 14_533
  @cleaner 14_503
  @quest 7_636

  @demons %{@artorius => 14_535, @franklin => 14_534, @nelson => 14_530, @simone => @seductress}
  @unmasking_emotes %{@artorius => 15, @franklin => 25, @nelson => 11, @simone => 22}
  @laugh 11
  @show_face "Show me your real face, demon."

  @amiable 0
  @unmasking 1
  @unmasked 2
  @restless 3

  @emote_after_ms 5_000
  @unmask_after_ms 10_000
  @patience_ms 1_200_000
  @banished_s 900
  @cleaner_lifetime_ms 1_200_000
  @guard_ms 1_000
  @precious_guard_ms 2_000
  @split_check_ms 2_500

  @demonic_frenzy 23_257
  @demonic_doom 23_298
  @stinging_trauma 23_299
  @serpent_stings [13_555, 25_295]
  @entropic_sting 23_260
  @scorpid_sting 14_277
  @soul_flame 23_272
  @creeping_doom 23_589
  @dreadful_fright 23_275
  @crippling_clip 23_279
  @wing_clip 14_268
  @frost_trap_aura 13_810
  @temptress_kiss 23_205
  @chain_lightning 23_206
  @silence 23_207
  @viper_sting 14_280
  @fools_plight 23_504
  @immune_all 29_230

  @poisoned 9_786
  @frenzied 7_797
  @immobilized 9_785
  @silenced 9_762
  @cleaner_aggro 9_726

  @doom_reach 25
  @fright_reach 5
  @partner_reach 30
  @precious_search 100
  @follow {2.0, 0.0, 0.0, :math.pi() / 2}

  @hunter_class_mask 4
  @incomplete 1
  @at_most 2
  @at_least 1
  @gossip_flag 0x1
  @npc_flags_field 147
  @remove_flags 2
  @current_position 1
  @spawn_position 2
  @triggered 0x02
  @demon_victim 1
  @no_attack -1
  @timed_or_dead_despawn 1
  @dead_despawn 7
  @follow_leader 15
  @idle 0
  @waypoints 2
  @script 1

  @impl CreatureScript
  def entries, do: Map.keys(@demons) ++ [@precious, @cleaner]

  @impl CreatureScript
  def events(@precious = entry) do
    unmasked = CreatureScript.only_in_phases([@unmasked])

    [
      CreatureScript.event(entry, 1, :spawned, [follow_simone()]),
      CreatureScript.event(entry, 2, :aggro, [call_for_help()], inverse_phase_mask: unmasked),
      every(entry, 3, :timer_in_combat, @precious_guard_ms, [crowded(entry)], unmasked),
      every(entry, 4, :timer_ooc, @split_check_ms, [partner(@seductress, evade_if_fighting())], unmasked),
      CreatureScript.event(entry, 5, :evade, [mourn_simone()], inverse_phase_mask: unmasked)
    ]
  end

  def events(@cleaner = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [cast_self(@immune_all, @triggered)]),
      CreatureScript.event(entry, 2, :aggro, [talk(@cleaner_aggro)]),
      CreatureScript.event(entry, 3, :evade, [despawn(0)]),
      every(entry, 4, :timer_ooc, 3_000, [despawn(0)], 0)
    ]
  end

  def events(entry) do
    demon = CreatureScript.only_in_phases([@unmasked, @restless])

    [
      CreatureScript.event(entry, 1, :spawned, spawned(entry)),
      CreatureScript.event(entry, 2, :script_event, unmask(entry),
        inverse_phase_mask: CreatureScript.only_in_phases([@amiable])
      ),
      CreatureScript.event(entry, 3, :evade, recall(entry) ++ [wait_out_patience()], inverse_phase_mask: demon),
      every(entry, 4, :timer_ooc, @guard_ms, slip_away(entry), CreatureScript.only_in_phases([@restless])),
      CreatureScript.event(entry, 5, :aggro, banish(entry), condition: not_a_hunter(), inverse_phase_mask: demon),
      every(entry, 6, :timer_in_combat, @guard_ms, [crowded(entry)], demon)
    ] ++ demon_events(entry, demon)
  end

  @impl CreatureScript
  def gossip do
    Map.new([@franklin, @simone], fn entry ->
      option = %Gossip.Option{text: @show_face, condition: stave_incomplete(), steps: call_out(entry)}
      {entry, %Gossip{options: [option]}}
    end)
  end

  defp call_out(@simone), do: [%ScriptStep{command: :send_script_event}, emote(@laugh)]
  defp call_out(_entry), do: [%ScriptStep{command: :send_script_event}]

  defp stave_incomplete, do: %Condition{type: :quest_taken, value1: @quest, value2: @incomplete}

  defp spawned(@simone), do: [home(@spawn_position), default_movement(@waypoints), summon_precious()]
  defp spawned(_entry), do: [home(@spawn_position), default_movement(@waypoints)]

  defp unmask(entry) do
    [
      %ScriptStep{command: :movement, datalong: @idle},
      hide_gossip(),
      phase(@unmasking),
      CreatureScript.timed(
        [at(@emote_after_ms, emote(Map.fetch!(@unmasking_emotes, entry)))] ++
          Enum.map(true_form(entry), &at(@unmask_after_ms, &1)) ++
          [at(@unmask_after_ms + @patience_ms, phase(@restless))]
      )
    ]
  end

  defp true_form(entry) do
    [
      %ScriptStep{command: :update_entry, datalong: Map.fetch!(@demons, entry)},
      home(@current_position),
      default_movement(@idle),
      phase(@unmasked)
    ] ++ unmasked(entry)
  end

  defp unmasked(@nelson), do: [%ScriptStep{command: :add_aura, datalong: @soul_flame}]

  defp unmasked(@simone) do
    [
      precious(%ScriptStep{
        command: :start_script,
        datalong: @script,
        dataint: 100,
        sub_scripts: %{@script => [%ScriptStep{command: :update_entry, datalong: @devourer}, phase(@unmasked)]}
      })
    ]
  end

  defp unmasked(_entry), do: []

  defp demon_events(@artorius = entry, demon) do
    [
      CreatureScript.event(entry, 7, :timer_in_combat, [cast_self(@demonic_frenzy, 0)],
        param1: 5_000,
        param2: 8_000,
        param3: 15_000,
        param4: 20_000,
        inverse_phase_mask: demon
      ),
      every(entry, 8, :timer_in_combat, 7_500, [within_reach(cast_victim(@demonic_doom))], demon)
    ] ++
      for {spell_id, index} <- Enum.with_index(@serpent_stings, 9) do
        sting(entry, index, spell_id, [cast_self(@stinging_trauma, @triggered), talk(@poisoned)], demon)
      end
  end

  defp demon_events(@franklin = entry, demon) do
    [
      every(entry, 7, :timer_in_combat, 5_000, 15_000, [cast_self(@demonic_frenzy, 0), talk(@frenzied)], demon),
      sting(
        entry,
        8,
        @scorpid_sting,
        [%ScriptStep{command: :remove_aura, datalong: @demonic_frenzy}, cast_self(@entropic_sting, @triggered)],
        demon
      )
    ]
  end

  defp demon_events(@nelson = entry, demon) do
    [
      CreatureScript.event(entry, 7, :timer_in_combat, [cast_self(@creeping_doom, 0)],
        param1: 3_000,
        param2: 6_000,
        param3: 15_000,
        param4: 15_000,
        inverse_phase_mask: demon
      ),
      CreatureScript.event(entry, 8, :timer_in_combat, [cast_victim(@dreadful_fright)],
        param1: 10_000,
        param2: 15_000,
        param3: 15_000,
        param4: 20_000,
        condition: %Condition{type: :distance_to_target, value1: @fright_reach, value2: @at_least},
        inverse_phase_mask: demon
      ),
      sting(entry, 9, @wing_clip, [cast_self(@crippling_clip, @triggered), talk(@immobilized)], demon),
      CreatureScript.event(entry, 10, :aura, [%ScriptStep{command: :remove_aura, datalong: @soul_flame}],
        param1: @frost_trap_aura,
        param2: 1,
        param3: @guard_ms,
        param4: @guard_ms,
        inverse_phase_mask: demon
      )
    ]
  end

  defp demon_events(@simone = entry, demon) do
    [
      CreatureScript.event(entry, 7, :timer_in_combat, [cast_victim(@fools_plight)],
        param1: 5_000,
        param2: 10_000,
        param3: 5_000,
        param4: 10_000,
        inverse_phase_mask: CreatureScript.only_in_phases([@amiable, @unmasking])
      ),
      CreatureScript.event(entry, 8, :timer_in_combat, [cast_victim(@temptress_kiss)],
        param1: 3_000,
        param2: 6_000,
        param3: 45_000,
        param4: 45_000,
        inverse_phase_mask: demon
      ),
      CreatureScript.event(entry, 9, :timer_in_combat, [cast_victim(@chain_lightning)],
        param1: 3_000,
        param2: 6_000,
        param3: 8_000,
        param4: 12_000,
        inverse_phase_mask: demon
      ),
      sting(entry, 10, @viper_sting, [cast_self(@silence, @triggered), talk(@silenced)], demon),
      CreatureScript.event(entry, 11, :aggro, [call_for_help()], inverse_phase_mask: demon),
      every(entry, 12, :timer_ooc, @split_check_ms, [partner(@devourer, evade_if_fighting())], demon)
    ]
  end

  defp banish(entry), do: [summon_cleaner()] ++ dismiss(entry) ++ [despawn(@banished_s)]

  defp slip_away(entry), do: dismiss(entry) ++ [despawn(@banished_s)]

  defp recall(@nelson), do: [%ScriptStep{command: :remove_guardians}]
  defp recall(_entry), do: []

  defp dismiss(@nelson), do: recall(@nelson)
  defp dismiss(@simone), do: [partner(@devourer, despawn(0))]
  defp dismiss(@precious), do: [partner(@seductress, despawn(@banished_s))]
  defp dismiss(_entry), do: []

  defp crowded(entry) do
    %ScriptStep{
      command: :start_script,
      datalong: @script,
      dataint: 100,
      target_type: :hostile_second_aggro,
      sub_scripts: %{@script => banish(entry)}
    }
  end

  defp wait_out_patience, do: CreatureScript.timed([at(@patience_ms, phase(@restless))])

  defp not_a_hunter do
    %Condition{
      type: :and,
      reverse?: true,
      children: [
        %Condition{type: :is_player},
        %Condition{type: :race_class, value1: 0, value2: @hunter_class_mask}
      ]
    }
  end

  defp summon_cleaner do
    %ScriptStep{
      command: :summon_creature,
      datalong: @cleaner,
      datalong2: @cleaner_lifetime_ms,
      dataint2: @script,
      dataint3: @demon_victim,
      dataint4: @timed_or_dead_despawn,
      sub_scripts: %{@script => [%ScriptStep{command: :attack_start}]}
    }
  end

  defp summon_precious do
    %ScriptStep{
      command: :summon_creature,
      datalong: @precious,
      dataint3: @no_attack,
      dataint4: @dead_despawn,
      target_self?: true,
      condition: %Condition{type: :nearby_creature, value1: @precious, value2: @precious_search, reverse?: true}
    }
  end

  defp follow_simone do
    %ScriptStep{
      command: :movement,
      datalong: @follow_leader,
      target_type: :nearest_creature_with_entry,
      target_param1: @simone,
      target_param2: @partner_reach,
      position: @follow
    }
  end

  defp mourn_simone do
    %{
      despawn(0)
      | target_self?: true,
        condition: %Condition{type: :nearby_creature, value1: @seductress, value2: @precious_search, reverse?: true}
    }
  end

  defp evade_if_fighting,
    do: %ScriptStep{command: :enter_evade, condition: %Condition{type: :in_combat, swap_targets?: true}}

  defp precious(%ScriptStep{} = step), do: partner(@precious, step)

  defp partner(entry, %ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @partner_reach,
        swap_final?: true
    }
  end

  defp within_reach(%ScriptStep{} = step),
    do: %{step | condition: %Condition{type: :distance_to_target, value1: @doom_reach, value2: @at_most}}

  defp sting(entry, index, spell_id, steps, phase_mask) do
    CreatureScript.event(entry, index, :hit_by_spell, steps, param1: spell_id, inverse_phase_mask: phase_mask)
  end

  defp every(entry, index, event_type, every_ms, steps, phase_mask),
    do: every(entry, index, event_type, every_ms, every_ms, steps, phase_mask)

  defp every(entry, index, event_type, first_ms, every_ms, steps, phase_mask) do
    CreatureScript.event(entry, index, event_type, steps,
      param1: first_ms,
      param2: first_ms,
      param3: every_ms,
      param4: every_ms,
      inverse_phase_mask: phase_mask
    )
  end

  defp call_for_help, do: %ScriptStep{command: :call_for_help, position: {@partner_reach, 0.0, 0.0, 0.0}}

  defp hide_gossip,
    do: %ScriptStep{
      command: :modify_flags,
      datalong: @npc_flags_field,
      datalong2: @gossip_flag,
      datalong3: @remove_flags
    }

  defp home(mode), do: %ScriptStep{command: :set_home_position, datalong: mode}
  defp default_movement(type), do: %ScriptStep{command: :set_default_movement, datalong: type}
  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}
  defp emote(emote_id), do: %ScriptStep{command: :emote, datalong: emote_id}
  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp despawn(respawn_s), do: %ScriptStep{command: :despawn, datalong2: respawn_s}

  defp cast_self(spell_id, flags),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}
end
