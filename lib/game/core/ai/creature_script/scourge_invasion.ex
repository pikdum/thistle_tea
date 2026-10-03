defmodule ThistleTea.Game.Core.AI.CreatureScript.ScourgeInvasion do
  @moduledoc """
  vmangos `scourge_invasion` creature AIs.

  The Mouth of Kel'Thuzad (`MouthAI`) taunts its zone every two and a half
  minutes to an hour. Over an invaded zone it answers
  `World.System.ScourgeInvasion`: script event 7 proclaims the attack, and
  script event 8 concedes the zone and departs.

  Each camp's Necrotic Shard keeps in touch with the necropolis overhead
  through purple bolts. Every thirty-five seconds the shard's communique timer
  sends one up to the camp's relay, the relay passes it to the necropolis
  proxy, and the proxy to the necropolis. That starts the necropolis's own
  fifteen-second timer, whose bolts come back down through every proxy and
  relay to the camps beneath.

  A damaged shard that falls restores everyone around it with Soul Revival
  and sends a death bolt down the same chain: relay, then proxy, then the
  necropolis's health, each relay or proxy leaving once its bolt lands. The
  third death bolt to reach a necropolis's health destroys it, and it brings
  the necropolis down with it.

  A Cultist Engineer whose ritual a player disrupts with eight Necrotic Runes
  dies, and a Shadow of Doom rises in its place. The Shadow is immune to the
  player for five seconds, then attacks with Mind Flay and Fear. Its death
  strikes the damaged shard for a quarter of its health.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @mouth 16_995
  @relay 16_386
  @proxy 16_398
  @necropolis 16_401
  @necropolis_health 16_421
  @shard 16_136
  @damaged_shard 16_172
  @cultist 16_230
  @shadow_of_doom 16_143

  @necropolis_objects [181_154, 181_373, 181_374, 181_215, 181_223]

  @camp_to_relay 28_281
  @relay_to_proxy 28_365
  @proxy_to_necropolis 28_367
  @necropolis_timer 28_395
  @necropolis_to_proxies 28_373
  @proxy_to_relay 28_366
  @relay_to_camp 28_326
  @camp_receives_communique 28_449
  @death_bolt 28_351
  @zap_necropolis 28_386
  @despawner_other 28_349
  @soul_revival 28_681
  @zap_crystal_corpse 28_056
  @quiet_suicide 3617
  @spawn_smoke 10_389
  @mind_flay 16_568
  @fear 12_542

  @necrotic_rune 22_484
  @runes_per_shadow 8
  @disrupt_ritual 7166

  @zone_start 7
  @zone_stop 8
  @zone_yell 6
  @triggered 0x02
  @aura_not_present 0x20
  @set_flags 1
  @remove_flags 2
  @unit_flags_field 46
  @immune_to_player 0x100
  @timed_or_dead_despawn 1
  @hour_ms 3_600_000
  @shadow_script 1
  @chain_reach 200
  @necropolis_reach 10
  @fallen_respawn_s 21_600
  @increment 1

  @attack_starts [13_121, 13_125]
  @attack_ends [13_165, 13_164, 13_163]
  @taunts [13_126, 13_124, 13_122, 13_123]
  @shadow_threats [12_420, 12_421, 12_422, 12_243]
  @fewest_taunt_ms 150_000
  @most_taunt_ms 3_600_000

  @impl CreatureScript
  def entries,
    do: [@mouth, @relay, @proxy, @necropolis, @necropolis_health, @shard, @damaged_shard, @cultist, @shadow_of_doom]

  @impl CreatureScript
  def events(@mouth) do
    [
      CreatureScript.event(@mouth, 1, :timer_ooc, [zone_yell(@taunts)],
        param1: @fewest_taunt_ms,
        param2: @most_taunt_ms,
        param3: @fewest_taunt_ms,
        param4: @most_taunt_ms
      ),
      CreatureScript.event(@mouth, 2, :script_event, [zone_yell(@attack_starts)], param1: @zone_start, param2: 0),
      CreatureScript.event(@mouth, 3, :script_event, [zone_yell(@attack_ends), %ScriptStep{command: :despawn}],
        param1: @zone_stop,
        param2: 0
      )
    ]
  end

  def events(@relay) do
    [
      hit(@relay, 1, @camp_to_relay, [cast_self(@relay_to_proxy)]),
      hit(@relay, 2, @proxy_to_relay, [cast_self(@relay_to_camp)]),
      hit(@relay, 3, @death_bolt, [cast_at(@proxy, @chain_reach, @death_bolt)]),
      CreatureScript.event(@relay, 4, :spell_hit_target, [depart()], param1: @death_bolt, param2: -1)
    ]
  end

  def events(@proxy) do
    [
      hit(@proxy, 1, @necropolis_to_proxies, [cast_self(@proxy_to_relay)]),
      hit(@proxy, 2, @relay_to_proxy, [cast_self(@proxy_to_necropolis)]),
      hit(@proxy, 3, @death_bolt, [cast_at(@necropolis_health, @chain_reach, @death_bolt)]),
      CreatureScript.event(@proxy, 4, :spell_hit_target, [depart()], param1: @death_bolt, param2: -1)
    ]
  end

  def events(@necropolis) do
    [
      hit(@necropolis, 1, @proxy_to_necropolis, [cast_self(@necropolis_timer, @triggered + @aura_not_present)]),
      hit(@necropolis, 2, @despawner_other, Enum.map(@necropolis_objects, &remove_object/1) ++ [depart()])
    ]
  end

  def events(@necropolis_health) do
    [
      CreatureScript.event(@necropolis_health, 1, :spawned, [%ScriptStep{command: :invincibility, datalong: 1}]),
      hit(@necropolis_health, 2, @death_bolt, [cast_self(@zap_necropolis)]),
      hit(@necropolis_health, 3, @zap_necropolis, [%{die() | target_self?: true}],
        inverse_phase_mask: CreatureScript.only_in_phases([2])
      ),
      hit(
        @necropolis_health,
        4,
        @zap_necropolis,
        [%ScriptStep{command: :set_phase, datalong: 1, datalong2: @increment}],
        inverse_phase_mask: CreatureScript.only_in_phases([0, 1])
      ),
      CreatureScript.event(@necropolis_health, 5, :death, [
        cast_at(@necropolis, @necropolis_reach, @despawner_other),
        depart(1_000)
      ])
    ]
  end

  def events(@shard), do: [hit(@shard, 1, @relay_to_camp, [cast_self(@camp_receives_communique)])]

  def events(@damaged_shard) do
    [
      hit(@damaged_shard, 1, @relay_to_camp, [cast_self(@camp_receives_communique)]),
      hit(@damaged_shard, 2, @zap_crystal_corpse, [
        %ScriptStep{command: :deal_damage, datalong: 25, datalong2: 1, target_self?: true}
      ]),
      CreatureScript.event(@damaged_shard, 3, :death, [
        cast_self(@soul_revival),
        cast_at(@relay, @chain_reach, @death_bolt)
      ])
    ]
  end

  def events(@cultist) do
    [
      CreatureScript.event(
        @cultist,
        1,
        :script_event,
        [
          %ScriptStep{command: :remove_item, datalong: @necrotic_rune, datalong2: @runes_per_shadow},
          summon_shadow(),
          cast_self(@quiet_suicide)
        ],
        param1: @disrupt_ritual,
        param2: 0
      )
    ]
  end

  def events(@shadow_of_doom) do
    [
      CreatureScript.event(@shadow_of_doom, 1, :timer_in_combat, [cast_victim(@mind_flay)],
        param1: 2_000,
        param2: 2_000,
        param3: 6_500,
        param4: 13_000
      ),
      CreatureScript.event(@shadow_of_doom, 2, :timer_in_combat, [cast_victim(@fear)],
        param1: 2_000,
        param2: 2_000,
        param3: 14_500,
        param4: 14_500
      ),
      CreatureScript.event(@shadow_of_doom, 3, :death, [cast_self(@zap_crystal_corpse)])
    ]
  end

  def events(_entry), do: []

  defp summon_shadow do
    %ScriptStep{
      command: :summon_creature,
      datalong: @shadow_of_doom,
      datalong2: @hour_ms,
      dataint2: @shadow_script,
      dataint4: @timed_or_dead_despawn,
      sub_scripts: %{@shadow_script => shadow_arrival()}
    }
  end

  defp shadow_arrival do
    [
      say(@shadow_threats),
      cast_self(@spawn_smoke),
      unit_flags(@set_flags, @immune_to_player),
      %{unit_flags(@remove_flags, @immune_to_player) | delay_ms: 5_000},
      %ScriptStep{command: :attack_start, delay_ms: 5_000}
    ]
  end

  defp hit(entry, index, spell_id, steps, opts \\ []) do
    CreatureScript.event(entry, index, :hit_by_spell, steps, Keyword.merge([param1: spell_id, param2: -1], opts))
  end

  defp cast_self(spell_id, flags \\ @triggered),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}

  defp cast_at(entry, reach, spell_id) do
    %ScriptStep{
      command: :cast_spell,
      datalong: spell_id,
      datalong2: @triggered,
      target_type: :nearest_creature_with_entry,
      target_param1: entry,
      target_param2: reach
    }
  end

  defp remove_object(entry) do
    %ScriptStep{
      command: :remove_object,
      target_type: :nearest_game_object_with_entry,
      target_param1: entry,
      target_param2: @necropolis_reach
    }
  end

  defp depart(delay_ms \\ 0), do: %ScriptStep{command: :despawn, datalong: delay_ms, datalong2: @fallen_respawn_s}

  defp die, do: %ScriptStep{command: :deal_damage, datalong: 100, datalong2: 1}

  defp unit_flags(mode, flags),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: flags, datalong3: mode}

  defp say(texts), do: talk(texts, 0)

  defp zone_yell(texts), do: talk(texts, @zone_yell)

  defp talk(texts, chat_type) do
    [dataint, dataint2, dataint3, dataint4] = Enum.take(texts ++ [0, 0, 0], 4)

    %ScriptStep{
      command: :talk,
      datalong: chat_type,
      dataint: dataint,
      dataint2: dataint2,
      dataint3: dataint3,
      dataint4: dataint4
    }
  end
end
