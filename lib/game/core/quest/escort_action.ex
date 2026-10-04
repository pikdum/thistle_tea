defmodule ThistleTea.Game.Core.Quest.EscortAction do
  @moduledoc """
  The action vocabulary escort and follower quests are written in, lowered
  into the generic script commands the creature interpreter runs.

  Actions are `{:say, text_id}` (spoken to the player),
  `{:say_by, entry, text_id}` (spoken by the nearest creature of that entry),
  `{:emote, emote_id}`, `{:emote_by, entry, emote_id}` (played by the
  nearest creature of that entry), `{:stand, stand_state}`,
  `{:faction, faction_id}` (until respawn), `:run`, `:walk`,
  `{:add_aura, spell_id}`, `{:remove_aura, spell_id}`, `{:unit_flags, mask}`
  and `{:remove_unit_flags, mask}` (set or cleared until respawn),
  `{:npc_flags, mask}` (sets npc flags back, as a questgiver that ends its own
  escort does), `{:pause, duration_ms}` (stops the escort at its point for
  that long, vmangos `SetEscortPaused`), `{:cast, spell_id}` (cast on itself,
  triggered; `{:cast, spell_id, triggered?: false}` casts it with its cast
  time), `{:face, entry}` (turns to the nearest creature of that entry),
  `{:signal, entry, event_id}` (sends that creature a script event, for a
  script port that reacts to it), `{:invincible, health_pct}` (never falls
  below that share of its health), `{:attack, :player}` (turns on the
  player, given a hostile faction first), `:fail` (fails the quest for the
  player and their group), `:die` (ends the quest's map event, then kills
  the escortee), `{:event_phase, phase}` (the escortee's EventAI phase, for
  a script port that reacts to it), `:abort` (ends the quest's map event as
  a failure, which fails the quest and respawns the escortee, vmangos
  `ResetEscort`), `{:summon, entry, position, opts}`,
  `{:summon_object, entry, position, duration_ms}` (unattached, so players
  can open it),
  `{:object_state, entry, state}` (sets the state of the nearest game object
  of that entry), and `{:after, delay_ms, action}`.
  `{:await, timeout_ms, actions, expired_actions}` stops the escort at its
  point until a script releases it (`release_waypoints`), then runs
  `actions`, or runs `expired_actions` if nothing does within `timeout_ms`.
  `{:hold, actions}` stops the escort at its
  point until every creature the escortee summoned from then on is gone, for
  at most 400 s, then runs `actions`. It must not be delayed, and it must
  come before the summons it waits for and before any action another
  creature performs (`say_by`, `emote_by`, `signal`), which holds back the
  escortee's remaining steps until that creature answers. A summon despawns per
  `despawn: {type, delay_ms}` (vmangos `TempSummonType` names), attacks the
  escortee, the player, or nothing per `attack:`, and runs the actions in
  `script:`. It comes `count:` at once, each on a random walkable point within
  `scatter:` yards of its position, which may be `:player` for the player's
  feet.

  The phase says where the steps run: `:accept` and `:arrival` steps are
  given the player as their target, `:point` steps reach the player through
  the quest's map event, and `:summon` steps run on the summoned creature.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep

  @summon_script 2
  @unit_flags_field 46
  @npc_flags_field 147
  @set_flags 1
  @remove_flags 2
  @restore_on_respawn 1
  @speaker_radius 150
  @percent 1
  @attack_none -1
  @attack_provided 0
  @attack_self 8
  @attack_event_target 23
  @hold_ms 400_000
  @event_success 1
  @event_failure 0
  @hold_release_script 1
  @hold_expired_script 2
  @signal_hold 1
  @object_radius 40
  @unattached_object 1
  @triggered 0x02

  @despawn_types %{
    timed_or_dead: 1,
    timed_or_corpse: 2,
    timed: 3,
    timed_out_of_combat: 4,
    corpse: 5,
    corpse_timed: 6,
    dead: 7
  }

  def summon_entries(actions) when is_list(actions) do
    actions |> Enum.flat_map(&summon_entry/1) |> Enum.uniq()
  end

  defp summon_entry({:after, _delay_ms, action}), do: summon_entry(action)
  defp summon_entry({:hold, actions}), do: Enum.flat_map(actions, &summon_entry/1)

  defp summon_entry({:await, _timeout_ms, actions, expired}), do: Enum.flat_map(actions ++ expired, &summon_entry/1)

  defp summon_entry({:summon, entry, _position, _opts}), do: [entry]
  defp summon_entry(_action), do: []

  def steps({:after, delay_ms, action}, quest_id, phase) when is_integer(delay_ms) do
    action |> steps(quest_id, phase) |> Enum.map(&%{&1 | delay_ms: &1.delay_ms + delay_ms})
  end

  def steps({:say, text_id}, quest_id, phase),
    do: [player_target(%ScriptStep{command: :talk, dataint: text_id}, quest_id, phase)]

  def steps({:say_by, entry, text_id}, _quest_id, _phase) do
    [
      %ScriptStep{
        command: :talk,
        dataint: text_id,
        target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @speaker_radius,
        swap_final?: true
      }
    ]
  end

  def steps({:emote, emote_id}, _quest_id, _phase), do: [%ScriptStep{command: :emote, datalong: emote_id}]

  def steps({:emote_by, entry, emote_id}, _quest_id, _phase) do
    [
      %ScriptStep{
        command: :emote,
        datalong: emote_id,
        target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @speaker_radius,
        swap_final?: true
      }
    ]
  end

  def steps({:stand, stand_state}, _quest_id, _phase), do: [%ScriptStep{command: :stand_state, datalong: stand_state}]

  def steps({:faction, faction_id}, _quest_id, _phase) do
    [%ScriptStep{command: :set_faction, datalong: faction_id, datalong2: @restore_on_respawn}]
  end

  def steps({:event_phase, event_phase}, _quest_id, _phase),
    do: [%ScriptStep{command: :set_phase, datalong: event_phase}]

  def steps(:run, _quest_id, _phase), do: [%ScriptStep{command: :set_run, datalong: 1}]
  def steps(:walk, _quest_id, _phase), do: [%ScriptStep{command: :set_run, datalong: 0}]
  def steps({:add_aura, spell_id}, _quest_id, _phase), do: [%ScriptStep{command: :add_aura, datalong: spell_id}]
  def steps({:remove_aura, spell_id}, _quest_id, _phase), do: [%ScriptStep{command: :remove_aura, datalong: spell_id}]

  def steps({:unit_flags, mask}, _quest_id, _phase) do
    [%ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: mask, datalong3: @set_flags}]
  end

  def steps({:remove_unit_flags, mask}, _quest_id, _phase) do
    [%ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: mask, datalong3: @remove_flags}]
  end

  def steps({:npc_flags, mask}, _quest_id, _phase),
    do: [%ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: mask, datalong3: @set_flags}]

  def steps({:pause, duration_ms}, _quest_id, _phase),
    do: [%ScriptStep{command: :hold_waypoints, datalong: duration_ms, datalong2: @signal_hold}]

  def steps({:cast, spell_id}, quest_id, phase), do: steps({:cast, spell_id, []}, quest_id, phase)

  def steps({:cast, spell_id, opts}, _quest_id, _phase) do
    flags = if Keyword.get(opts, :triggered?, true), do: @triggered, else: 0
    [%ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}]
  end

  def steps({:face, entry}, _quest_id, _phase),
    do: [
      %ScriptStep{
        command: :turn_to,
        target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @speaker_radius
      }
    ]

  def steps({:signal, entry, event_id}, _quest_id, _phase) do
    [
      %ScriptStep{
        command: :send_script_event,
        datalong: event_id,
        target_type: :nearest_creature_with_entry,
        target_param1: entry,
        target_param2: @speaker_radius,
        swap_final?: true
      }
    ]
  end

  def steps({:invincible, health_pct}, _quest_id, _phase),
    do: [%ScriptStep{command: :invincibility, datalong: health_pct, datalong2: @percent}]

  def steps({:hold, actions}, quest_id, phase) when is_list(actions) do
    release = Enum.flat_map(actions, &steps(&1, quest_id, phase))

    [
      %ScriptStep{
        command: :hold_waypoints,
        datalong: @hold_ms,
        sub_scripts: %{@hold_release_script => release}
      }
    ]
  end

  def steps({:await, timeout_ms, actions, expired_actions}, quest_id, phase)
      when is_integer(timeout_ms) and is_list(actions) and is_list(expired_actions) do
    [
      %ScriptStep{
        command: :hold_waypoints,
        datalong: timeout_ms,
        datalong2: @signal_hold,
        sub_scripts: %{
          @hold_release_script => Enum.flat_map(actions, &steps(&1, quest_id, phase)),
          @hold_expired_script => Enum.flat_map(expired_actions, &steps(&1, quest_id, phase))
        }
      }
    ]
  end

  def steps(:abort, quest_id, _phase),
    do: [%ScriptStep{command: :end_map_event, datalong: quest_id, datalong2: @event_failure}]

  def steps({:summon_object, entry, {_x, _y, _z, _o} = position, duration_ms}, _quest_id, _phase)
      when is_integer(duration_ms) do
    [
      %ScriptStep{
        command: :summon_object,
        datalong: entry,
        datalong2: div(duration_ms, 1_000),
        datalong3: @unattached_object,
        position: position
      }
    ]
  end

  def steps({:object_state, entry, state}, _quest_id, _phase) do
    [
      %ScriptStep{
        command: :set_game_object_state,
        datalong: state,
        target_type: :nearest_game_object_with_entry,
        target_param1: entry,
        target_param2: @object_radius
      }
    ]
  end

  def steps({:attack, :player}, quest_id, phase),
    do: [player_target(%ScriptStep{command: :attack_start}, quest_id, phase)]

  def steps(:die, quest_id, _phase) do
    [
      %ScriptStep{command: :end_map_event, datalong: quest_id, datalong2: @event_success},
      %ScriptStep{command: :deal_damage, datalong: 100, datalong2: @percent, target_self?: true}
    ]
  end

  def steps(:fail, quest_id, phase),
    do: [player_target(%ScriptStep{command: :fail_quest, datalong: quest_id}, quest_id, phase)]

  def steps({:summon, entry, :player, opts}, quest_id, phase),
    do: [player_target(%{summon(entry, nil, opts, quest_id, phase) | at_target?: true}, quest_id, phase)]

  def steps({:summon, entry, {_x, _y, _z, _o} = position, opts}, quest_id, phase),
    do: [summon(entry, position, opts, quest_id, phase)]

  defp summon(entry, position, opts, quest_id, phase) do
    {despawn_type, despawn_ms} = Keyword.get(opts, :despawn, {:timed_or_dead, 25_000})
    script = Enum.flat_map(Keyword.get(opts, :script, []), &steps(&1, quest_id, :summon))

    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: despawn_ms,
      dataint2: if(script == [], do: 0, else: @summon_script),
      dataint3: attack_type(Keyword.get(opts, :attack), phase),
      dataint4: Map.fetch!(@despawn_types, despawn_type),
      target_param1: quest_id,
      position: position,
      count: Keyword.get(opts, :count, 1),
      scatter: Keyword.get(opts, :scatter, 0.0),
      sub_scripts: if(script == [], do: %{}, else: %{@summon_script => script})
    }
  end

  defp attack_type(nil, _phase), do: @attack_none
  defp attack_type(:escort, _phase), do: @attack_self
  defp attack_type(:player, phase) when phase in [:accept, :arrival], do: @attack_provided
  defp attack_type(:player, _phase), do: @attack_event_target

  defp player_target(step, quest_id, :point), do: %{step | target_type: :map_event_target, target_param1: quest_id}
  defp player_target(step, _quest_id, _phase), do: step
end
