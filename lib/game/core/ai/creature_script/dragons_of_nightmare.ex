defmodule ThistleTea.Game.Core.AI.CreatureScript.DragonsOfNightmare do
  @moduledoc """
  vmangos `boss_dragon_of_nightmare` and its helpers: Ysondre, Lethon,
  Emeriss, and Taerar, the green dragons that the Dragons of Nightmare event
  brings to the Emerald Dream portals.

  On the pull each dragon marks the players around it with Mark of Nature. A
  marked player who dies wakes up stunned by its Aura of Nature until the mark
  fades. It breathes Noxious Breath at its victim, sweeps its tail, and lets
  out Seeping Fog, whose Dream Fogs drift between the players on its threat
  list and put them to sleep. It summons back a victim that runs out of
  reach. At 75, 50, and 25 percent health each dragon calls its own special:

  - Ysondre summons Demented Druid Spirits, three of them or three for every
    four players fighting her up to fifteen, each hunting a random player.
  - Lethon draws the spirits out of the players around him. Their Spirit
    Shades walk back to him and heal him if they reach him.
  - Emeriss casts Corruption of the Earth, and a player who dies under her
    Emeriss Aura grows a Putrid Mushroom from their corpse.
  - Taerar stuns himself, turns unselectable, and splits off three Shades of
    Taerar. He wakes when all three die or after two minutes. Each of his
    banishments counts its own three EventAI phases, so the two-minute timer
    of an earlier banishment cannot end a later one.

  Lethon's shades keep their own spirit model instead of copying the player
  they were drawn from, and are visible from the moment they appear. A dragon
  summons back a victim as soon as it stands thirty yards away instead of
  after six seconds out of melee reach.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @ysondre 14_887
  @lethon 14_888
  @emeriss 14_889
  @taerar 14_890
  @dragons [@ysondre, @lethon, @emeriss, @taerar]

  @dream_fog 15_224
  @demented_druid 15_260
  @spirit_shade 15_261
  @shade_of_taerar 15_302

  @mark_of_nature 25_041
  @aura_of_nature 25_044
  @seeping_fog_right 24_813
  @seeping_fog_left 24_814
  @noxious_breath 24_818
  @tail_sweep 15_847
  @summon_player 24_776
  @dream_fog_aura 24_777

  @lightning_wave 24_819
  @curse_of_thorns 16_247
  @moonfire 24_957
  @silence 6_726

  @shadow_bolt_whirl 24_834
  @draw_spirit 24_811
  @dark_offering 24_804

  @emeriss_aura 24_906
  @volatile_infection 24_928
  @corruption_of_the_earth 24_910

  @arcane_blast 24_857
  @bellowing_roar 22_686
  @shade_spells [24_841, 24_842, 24_843]
  @self_stun 24_883
  @acid_breath 24_839
  @poison_cloud 24_840

  @say_ysondre_aggro 10_880
  @say_summon_druids 10_881
  @say_summon_spirit_shades 10_882
  @say_lethon_aggro 10_883
  @say_corruption 10_884
  @say_emeriss_aggro 10_885
  @say_taerar_aggro 10_886
  @say_summon_taerar_shades 10_887

  @triggered 0x02
  @aura_not_present 0x20
  @players_only 0x02
  @mana_players_only 0x02 + 0x04
  @hostile_random 4
  @unit_fields_flags 46
  @not_selectable 0x02000000
  @set_flags 1
  @remove_flags 2
  @increment_phase 1
  @timed_out_of_combat 4
  @timed_or_dead 1
  @point_motion 9
  @shade_arrival 1
  @shades_timeout_event 1
  @shades_timeout_ms 120_000
  @specials [{1, 75}, {2, 50}, {3, 25}]

  @impl CreatureScript
  def entries, do: @dragons ++ [@dream_fog, @demented_druid, @spirit_shade, @shade_of_taerar]

  @impl CreatureScript
  def events(entry) when entry in @dragons do
    [
      CreatureScript.event(entry, 1, :aggro, [cast_self(@mark_of_nature, @triggered + @aura_not_present) | aggro(entry)]),
      CreatureScript.event(entry, 2, :timer_in_combat, [cast_self(@aura_of_nature)], param3: 3_000, param4: 5_000),
      awake(
        entry,
        3,
        :timer_in_combat,
        [cast_self(@seeping_fog_right, @triggered), cast_self(@seeping_fog_left, @triggered)],
        param1: 20_000,
        param2: 20_000,
        param3: 120_300,
        param4: 120_300
      ),
      awake(entry, 4, :timer_in_combat, [cast_victim(@noxious_breath)],
        param1: 7_000,
        param2: 10_000,
        param3: 9_000,
        param4: 11_000
      ),
      awake(entry, 5, :timer_in_combat, [cast_self(@tail_sweep)],
        param1: 10_000,
        param2: 10_000,
        param3: 6_000,
        param4: 8_000
      ),
      awake(entry, 6, :range, [cast_victim(@summon_player, @triggered)],
        param1: 30,
        param2: 500,
        param3: 6_000,
        param4: 6_000
      ),
      CreatureScript.event(entry, 7, :evade, evade(entry))
    ] ++
      Enum.map(@specials, fn {number, health_pct} ->
        awake(entry, 7 + number, :hp, special(entry, number),
          param1: health_pct,
          repeatable?: false,
          check_result?: true
        )
      end) ++ abilities(entry)
  end

  def events(@dream_fog) do
    retarget = [%ScriptStep{command: :attack_start, target_type: :owner_hostile_random, target_param1: @players_only}]

    [
      CreatureScript.event(@dream_fog, 1, :spawned, [cast_self(@dream_fog_aura, @triggered + @aura_not_present)]),
      CreatureScript.event(@dream_fog, 2, :timer_in_combat, retarget, param3: 6_000, param4: 10_000),
      CreatureScript.event(@dream_fog, 3, :timer_ooc, retarget, param3: 6_000, param4: 10_000)
    ]
  end

  def events(@demented_druid) do
    [
      CreatureScript.event(
        @demented_druid,
        1,
        :timer_in_combat,
        [cast_random(@curse_of_thorns, @players_only, @aura_not_present)],
        param1: 4_000,
        param2: 10_000,
        param3: 13_000,
        param4: 16_000
      ),
      CreatureScript.event(@demented_druid, 2, :timer_in_combat, [cast_victim(@moonfire)],
        param1: 1_000,
        param2: 5_000,
        param3: 3_000,
        param4: 6_000
      ),
      CreatureScript.event(
        @demented_druid,
        3,
        :timer_in_combat,
        [cast_random(@silence, @mana_players_only, @aura_not_present)],
        param1: 5_000,
        param2: 12_000,
        param3: 10_000,
        param4: 14_000
      )
    ]
  end

  def events(@spirit_shade) do
    walk_to_lethon = %ScriptStep{
      command: :move_to,
      delay_ms: 2_500,
      datalong: 2,
      datalong3: 1,
      datalong4: 2,
      dataint: @shade_arrival,
      position: {0.0, 0.0, 0.0, -1.0},
      target_type: :nearest_creature_with_entry,
      target_param1: @lethon,
      target_param2: 100
    }

    dark_offering = %ScriptStep{
      command: :cast_spell,
      datalong: @dark_offering,
      datalong2: @triggered,
      target_type: :nearest_creature_with_entry,
      target_param1: @lethon,
      target_param2: 100
    }

    [
      CreatureScript.event(@spirit_shade, 1, :spawned, [
        %ScriptStep{command: :set_react_state, datalong: 0},
        CreatureScript.timed([walk_to_lethon])
      ]),
      CreatureScript.event(
        @spirit_shade,
        2,
        :movement_inform,
        [dark_offering, %ScriptStep{command: :despawn, datalong: 300}],
        param1: @point_motion,
        param2: @shade_arrival
      )
    ]
  end

  def events(@shade_of_taerar) do
    [
      CreatureScript.event(@shade_of_taerar, 1, :timer_in_combat, [cast_victim(@acid_breath)],
        param1: 10_000,
        param2: 12_000,
        param3: 10_000,
        param4: 15_000
      ),
      CreatureScript.event(@shade_of_taerar, 2, :timer_in_combat, [cast_self(@poison_cloud)],
        param1: 8_000,
        param2: 15_000,
        param3: 15_000,
        param4: 20_000
      )
    ]
  end

  defp aggro(@ysondre), do: [talk(@say_ysondre_aggro)]

  defp aggro(@lethon), do: [cast_self(@shadow_bolt_whirl, @triggered + @aura_not_present), talk(@say_lethon_aggro)]

  defp aggro(@emeriss), do: [talk(@say_emeriss_aggro)]
  defp aggro(@taerar), do: [talk(@say_taerar_aggro)]

  defp evade(entry) do
    [
      %ScriptStep{command: :remove_guardians},
      remove_aura(@mark_of_nature),
      %ScriptStep{command: :set_phase, datalong: 0}
    ] ++ evade_extra(entry)
  end

  defp evade_extra(@lethon), do: [remove_aura(@shadow_bolt_whirl)]
  defp evade_extra(@taerar), do: unbanish()
  defp evade_extra(_entry), do: []

  defp special(@ysondre, _number) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @demented_druid,
        datalong2: 5_000,
        dataint3: @hostile_random,
        dataint4: @timed_out_of_combat,
        target_param1: @players_only,
        count: {:threat_players, 0.75, 3, 15}
      },
      talk(@say_summon_druids)
    ]
  end

  defp special(@lethon, _number), do: [abort_on_failure(cast_self(@draw_spirit)), talk(@say_summon_spirit_shades)]

  defp special(@emeriss, _number), do: [abort_on_failure(cast_self(@corruption_of_the_earth)), talk(@say_corruption)]

  defp special(@taerar, number) do
    first_phase = banished_phase(number, 1)

    [abort_on_failure(cast_self(@self_stun))] ++
      Enum.map(@shade_spells, &cast_self(&1, @triggered)) ++
      [
        %ScriptStep{
          command: :modify_flags,
          datalong: @unit_fields_flags,
          datalong2: @not_selectable,
          datalong3: @set_flags
        },
        talk(@say_summon_taerar_shades),
        %ScriptStep{command: :set_phase, datalong: first_phase},
        CreatureScript.timed([
          %ScriptStep{
            command: :send_script_event,
            delay_ms: @shades_timeout_ms,
            datalong: @shades_timeout_event,
            datalong2: number,
            target_self?: true
          }
        ])
      ]
  end

  defp abilities(@ysondre) do
    [
      awake(@ysondre, 11, :timer_in_combat, [cast_random(@lightning_wave, @players_only)],
        param1: 10_000,
        param2: 13_000,
        param3: 8_000,
        param4: 12_000
      )
    ]
  end

  defp abilities(@lethon) do
    [
      CreatureScript.event(
        @lethon,
        11,
        :spell_hit_target,
        [
          %ScriptStep{
            command: :summon_creature,
            datalong: @spirit_shade,
            datalong2: 60_000,
            dataint3: -1,
            dataint4: @timed_or_dead,
            at_target?: true
          }
        ],
        param1: @draw_spirit
      )
    ]
  end

  defp abilities(@emeriss) do
    [
      awake(@emeriss, 11, :timer_in_combat, [cast_self(@emeriss_aura)], param3: 10_000, param4: 10_000),
      awake(@emeriss, 12, :timer_in_combat, [cast_random(@volatile_infection, @players_only, @aura_not_present)],
        param1: 11_000,
        param2: 13_000,
        param3: 10_000,
        param4: 16_000
      )
    ]
  end

  defp abilities(@taerar) do
    shade_deaths =
      for number <- 3..1//-1, nth <- 3..1//-1 do
        phase = banished_phase(number, nth)
        steps = if nth == 3, do: unbanish() ++ [%ScriptStep{command: :remove_guardians}], else: [next_phase()]

        CreatureScript.event(@taerar, 10 + phase, :summoned_just_died, steps,
          param1: @shade_of_taerar,
          inverse_phase_mask: CreatureScript.only_in_phases([phase])
        )
      end

    timeouts =
      for number <- 1..3 do
        CreatureScript.event(@taerar, 20 + number, :script_event, unbanish(),
          param1: @shades_timeout_event,
          param2: number,
          inverse_phase_mask: CreatureScript.only_in_phases(Enum.map(1..3, &banished_phase(number, &1)))
        )
      end

    [
      awake(@taerar, 31, :timer_in_combat, [cast_random(@arcane_blast, @players_only)],
        param1: 11_000,
        param2: 13_000,
        param3: 10_000,
        param4: 16_000
      ),
      awake(@taerar, 32, :timer_in_combat, [cast_self(@bellowing_roar)],
        param1: 27_000,
        param2: 30_000,
        param3: 25_000,
        param4: 28_000
      )
    ] ++ shade_deaths ++ timeouts
  end

  defp banished_phase(number, nth), do: (number - 1) * 3 + nth

  defp unbanish do
    [
      remove_aura(@self_stun),
      %ScriptStep{
        command: :modify_flags,
        datalong: @unit_fields_flags,
        datalong2: @not_selectable,
        datalong3: @remove_flags
      },
      %ScriptStep{command: :set_phase, datalong: 0}
    ]
  end

  defp next_phase, do: %ScriptStep{command: :set_phase, datalong: 1, datalong2: @increment_phase}

  defp awake(entry, index, event_type, steps, opts),
    do:
      CreatureScript.event(
        entry,
        index,
        event_type,
        steps,
        [inverse_phase_mask: CreatureScript.only_in_phases([0])] ++ opts
      )

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_type: :victim}

  defp cast_random(spell_id, select_flags, flags \\ 0) do
    %ScriptStep{
      command: :cast_spell,
      datalong: spell_id,
      datalong2: flags,
      target_type: :hostile_random,
      target_param1: select_flags
    }
  end

  defp abort_on_failure(%ScriptStep{} = step), do: %{step | abort_on_failure?: true}

  defp remove_aura(spell_id), do: %ScriptStep{command: :remove_aura, datalong: spell_id}

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
end
