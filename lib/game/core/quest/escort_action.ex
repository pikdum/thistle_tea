defmodule ThistleTea.Game.Core.Quest.EscortAction do
  @moduledoc """
  The action vocabulary escort and follower quests are written in, lowered
  into the generic script commands the creature interpreter runs.

  Actions are `{:say, text_id}` (spoken to the player),
  `{:say_by, entry, text_id}` (spoken by the nearest creature of that entry),
  `{:emote, emote_id}`, `{:stand, stand_state}`, `{:faction, faction_id}`
  (until respawn), `:run`, `:walk`, `{:add_aura, spell_id}`,
  `{:remove_aura, spell_id}`, `{:remove_unit_flags, mask}` (until
  respawn), `{:invincible, health_pct}` (never falls below that share of its
  health), `:fail` (fails the quest for the player and their group),
  `{:event_phase, phase}` (the escortee's EventAI phase, for a script port
  that reacts to it), `{:summon, entry, position, opts}`, and
  `{:after, delay_ms, action}`. A summon despawns per
  `despawn: {type, delay_ms}` (vmangos `TempSummonType` names), attacks the
  escortee, the player, or nothing per `attack:`, and runs the actions in
  `script:`.

  The phase says where the steps run: `:accept` and `:arrival` steps are
  given the player as their target, `:point` steps reach the player through
  the quest's map event, and `:summon` steps run on the summoned creature.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep

  @summon_script 2
  @unit_flags_field 46
  @remove_flags 2
  @restore_on_respawn 1
  @speaker_radius 30
  @percent 1
  @attack_none -1
  @attack_provided 0
  @attack_self 8
  @attack_event_target 23

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

  def steps({:remove_unit_flags, mask}, _quest_id, _phase) do
    [%ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: mask, datalong3: @remove_flags}]
  end

  def steps({:invincible, health_pct}, _quest_id, _phase),
    do: [%ScriptStep{command: :invincibility, datalong: health_pct, datalong2: @percent}]

  def steps(:fail, quest_id, phase),
    do: [player_target(%ScriptStep{command: :fail_quest, datalong: quest_id}, quest_id, phase)]

  def steps({:summon, entry, {_x, _y, _z, _o} = position, opts}, quest_id, phase) do
    {despawn_type, despawn_ms} = Keyword.get(opts, :despawn, {:timed_or_dead, 25_000})
    script = Enum.flat_map(Keyword.get(opts, :script, []), &steps(&1, quest_id, :summon))

    [
      %ScriptStep{
        command: :summon_creature,
        datalong: entry,
        datalong2: despawn_ms,
        dataint2: if(script == [], do: 0, else: @summon_script),
        dataint3: attack_type(Keyword.get(opts, :attack), phase),
        dataint4: Map.fetch!(@despawn_types, despawn_type),
        target_param1: quest_id,
        position: position,
        sub_scripts: if(script == [], do: %{}, else: %{@summon_script => script})
      }
    ]
  end

  defp attack_type(nil, _phase), do: @attack_none
  defp attack_type(:escort, _phase), do: @attack_self
  defp attack_type(:player, phase) when phase in [:accept, :arrival], do: @attack_provided
  defp attack_type(:player, _phase), do: @attack_event_target

  defp player_target(step, quest_id, :point), do: %{step | target_type: :map_event_target, target_param1: quest_id}
  defp player_target(step, _quest_id, _phase), do: step
end
