defmodule ThistleTea.Game.Entity.Logic.Event do
  @moduledoc """
  Event structs produced by pure logic and queued on an entity's internal
  state; the boundary later drains them via `EventSink` and turns them into
  packets or process messages. Includes constructors for each event type.
  """
  defstruct [
    :type,
    :source_guid,
    :source_level,
    :target_guid,
    :spell_id,
    :triggering_spell_id,
    :school,
    :damage,
    :proc_damage,
    :amount,
    :health,
    :mana,
    :periodic?,
    :proc_type,
    :aura_type,
    :misc_value,
    :aura_slot,
    :duration_ms,
    :speed,
    :rooted?,
    :enabled?,
    :position,
    :item_id,
    :count,
    :reagents,
    :move_opts,
    :hit_guids,
    :misses,
    :resisted,
    :absorbed,
    :raw_targets,
    :cast_item_guid,
    :stand_state,
    :update_type,
    :cast_context,
    :target_role,
    :spell,
    :spells,
    :effect,
    :modifier_type,
    :effect_index,
    :operation,
    :attack,
    :channel_time_ms,
    :entry,
    :text,
    :chat_type,
    :emote_id,
    :steps,
    :summon,
    :respawn_delay_ms,
    :sound_id,
    :facing,
    :reason,
    :outcome,
    :crit?,
    :blocked,
    :slot,
    :range_yards,
    :resolve_targets?
  ]

  def spell_damage(source_guid, target_guid, spell, damage, opts \\ []) do
    %__MODULE__{
      type: :spell_damage,
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell.id,
      school: spell.school,
      damage: damage,
      proc_damage: Keyword.get(opts, :proc_damage),
      periodic?: Keyword.get(opts, :periodic?, false),
      proc_type: Keyword.get(opts, :proc_type, spell_damage_proc_type(opts)),
      resisted: Keyword.get(opts, :resisted, 0),
      absorbed: Keyword.get(opts, :absorbed, 0),
      crit?: Keyword.get(opts, :crit?, false),
      blocked: Keyword.get(opts, :blocked, 0)
    }
  end

  defp spell_damage_proc_type(opts) do
    if Keyword.get(opts, :periodic?, false), do: :deal_harmful_periodic, else: :deal_harmful_spell
  end

  def drain_power(target_guid, power_type) when is_integer(target_guid) and is_integer(power_type) do
    %__MODULE__{type: :drain_power, target_guid: target_guid, misc_value: power_type}
  end

  def grant_power(target_guid, power_type, amount)
      when is_integer(target_guid) and is_integer(power_type) and is_integer(amount) do
    %__MODULE__{type: :grant_power, target_guid: target_guid, misc_value: power_type, amount: amount}
  end

  def charge(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :charge, target_guid: target_guid}
  end

  def spell_log_miss(source_guid, target_guid, spell_id, reason)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(spell_id) and is_atom(reason) do
    %__MODULE__{
      type: :spell_log_miss,
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      reason: reason
    }
  end

  def aura_duration(slot, duration_ms) when is_integer(slot) and is_integer(duration_ms) do
    %__MODULE__{
      type: :aura_duration,
      aura_slot: slot,
      duration_ms: duration_ms
    }
  end

  def remove_aura(source_guid, target_guid, spell_id)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(spell_id) do
    %__MODULE__{type: :remove_aura, source_guid: source_guid, target_guid: target_guid, spell_id: spell_id}
  end

  def periodic_aura_log(source_guid, target_guid, spell, aura_type, amount, opts \\ [])
      when is_integer(source_guid) and is_integer(target_guid) and is_atom(aura_type) and is_integer(amount) do
    %__MODULE__{
      type: :periodic_aura_log,
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell.id,
      aura_type: aura_type,
      amount: amount,
      misc_value: Keyword.get(opts, :misc_value, 0)
    }
  end

  def movement_stopped do
    %__MODULE__{type: :movement_stopped}
  end

  def movement_speed_changed(speed) when is_number(speed) do
    %__MODULE__{type: :movement_speed_changed, speed: speed}
  end

  def movement_root_changed(rooted?) when is_boolean(rooted?) do
    %__MODULE__{type: :movement_root_changed, rooted?: rooted?}
  end

  def feather_fall_changed(enabled?) when is_boolean(enabled?) do
    %__MODULE__{type: :feather_fall_changed, enabled?: enabled?}
  end

  def hover_changed(enabled?) when is_boolean(enabled?) do
    %__MODULE__{type: :hover_changed, enabled?: enabled?}
  end

  def water_walk_changed(enabled?) when is_boolean(enabled?) do
    %__MODULE__{type: :water_walk_changed, enabled?: enabled?}
  end

  def heal_entity(target_guid, amount) when is_integer(target_guid) and is_integer(amount) do
    %__MODULE__{type: :heal_entity, target_guid: target_guid, amount: amount}
  end

  def heal_threat(source_guid, target_guid, amount)
      when is_integer(source_guid) and is_integer(target_guid) and is_number(amount) do
    %__MODULE__{type: :heal_threat, source_guid: source_guid, target_guid: target_guid, amount: amount}
  end

  def resurrect_request(source_guid, spell_id, health, mana)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(health) and is_integer(mana) do
    %__MODULE__{type: :resurrect_request, source_guid: source_guid, spell_id: spell_id, health: health, mana: mana}
  end

  def monster_move(opts \\ []) when is_list(opts) do
    %__MODULE__{type: :monster_move, move_opts: opts}
  end

  def spell_cast_result(spell_id) when is_integer(spell_id) do
    %__MODULE__{type: :spell_cast_result, spell_id: spell_id}
  end

  def spell_cast_failed(spell_id, reason) when is_integer(spell_id) and is_atom(reason) do
    %__MODULE__{type: :spell_cast_failed, spell_id: spell_id, reason: reason}
  end

  def spell_cooldown(source_guid, spell_id, cooldown_ms)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(cooldown_ms) do
    %__MODULE__{type: :spell_cooldown, source_guid: source_guid, spell_id: spell_id, duration_ms: cooldown_ms}
  end

  def spell_modifier(type, index, operation, amount)
      when type in [:flat, :pct] and is_integer(index) and is_integer(operation) and is_integer(amount) do
    %__MODULE__{
      type: :spell_modifier,
      modifier_type: type,
      effect_index: index,
      operation: operation,
      amount: amount
    }
  end

  def cooldown_event(source_guid, spell_id) when is_integer(source_guid) and is_integer(spell_id) do
    %__MODULE__{type: :cooldown_event, source_guid: source_guid, spell_id: spell_id}
  end

  def clear_cooldown(target_guid, spell_id) when is_integer(target_guid) and is_integer(spell_id) do
    %__MODULE__{type: :clear_cooldown, target_guid: target_guid, spell_id: spell_id}
  end

  def stand_state(stand_state) when is_integer(stand_state) do
    %__MODULE__{type: :stand_state, stand_state: stand_state}
  end

  def spell_start(source_guid, spell_id, cast_time_ms, raw_targets)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(cast_time_ms) and is_binary(raw_targets) do
    %__MODULE__{
      type: :spell_start,
      source_guid: source_guid,
      spell_id: spell_id,
      duration_ms: cast_time_ms,
      raw_targets: raw_targets
    }
  end

  def spell_go(source_guid, spell_id, hit_guids, raw_targets, cast_item_guid \\ nil, misses \\ [])
      when is_integer(source_guid) and is_integer(spell_id) and is_list(hit_guids) and is_binary(raw_targets) and
             is_list(misses) do
    %__MODULE__{
      type: :spell_go,
      source_guid: source_guid,
      spell_id: spell_id,
      hit_guids: hit_guids,
      misses: misses,
      raw_targets: raw_targets,
      cast_item_guid: cast_item_guid
    }
  end

  def channel_start(source_guid, spell_id, duration_ms)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(duration_ms) do
    %__MODULE__{
      type: :channel_start,
      source_guid: source_guid,
      spell_id: spell_id,
      channel_time_ms: duration_ms
    }
  end

  def channel_update(source_guid, time_ms) when is_integer(source_guid) and is_integer(time_ms) do
    %__MODULE__{
      type: :channel_update,
      source_guid: source_guid,
      channel_time_ms: time_ms
    }
  end

  def object_update(update_type \\ :values) do
    %__MODULE__{type: :object_update, update_type: update_type}
  end

  def deliver_attack(target_guid, attack) when is_integer(target_guid) and is_map(attack) do
    %__MODULE__{type: :deliver_attack, target_guid: target_guid, attack: attack}
  end

  def deliver_spell(target_guid, cast_context, spell) when is_integer(target_guid) do
    %__MODULE__{type: :deliver_spell, target_guid: target_guid, cast_context: cast_context, spell: spell}
  end

  def attack_start(source_guid, target_guid) when is_integer(source_guid) and is_integer(target_guid) do
    %__MODULE__{type: :attack_start, source_guid: source_guid, target_guid: target_guid}
  end

  def attack_stop(source_guid, target_guid) when is_integer(source_guid) and is_integer(target_guid) do
    %__MODULE__{type: :attack_stop, source_guid: source_guid, target_guid: target_guid}
  end

  def attack_not_in_range do
    %__MODULE__{type: :attack_not_in_range}
  end

  def attacker_gained(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :attacker_gained, target_guid: target_guid}
  end

  def threat_ref_gained(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :threat_ref_gained, target_guid: target_guid}
  end

  def threat_ref_lost(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :threat_ref_lost, target_guid: target_guid}
  end

  def drop_threat(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :drop_threat, target_guid: target_guid}
  end

  def drop_nearby_threat do
    %__MODULE__{type: :drop_nearby_threat}
  end

  def blade_flurry(target_guid, damage, spell_id)
      when is_integer(target_guid) and is_integer(damage) and damage > 0 and is_integer(spell_id) do
    %__MODULE__{type: :blade_flurry, target_guid: target_guid, damage: damage, spell_id: spell_id}
  end

  defguardp valid_secondary_melee?(target_guid, damage, spell_id, radius)
            when is_integer(target_guid) and is_integer(damage) and damage > 0 and is_integer(spell_id) and
                   is_number(radius) and radius > 0

  def secondary_melee(target_guid, damage, spell_id, radius)
      when valid_secondary_melee?(target_guid, damage, spell_id, radius) do
    %__MODULE__{
      type: :secondary_melee,
      target_guid: target_guid,
      damage: damage,
      spell_id: spell_id,
      range_yards: radius
    }
  end

  def attacker_lost(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :attacker_lost, target_guid: target_guid}
  end

  def tap_cleared do
    %__MODULE__{type: :tap_cleared}
  end

  def attack_outcome(attacker_guid, victim_guid, outcome, damage, spell_id, proc_damage \\ nil)
      when is_integer(attacker_guid) and is_integer(victim_guid) and is_atom(outcome) do
    %__MODULE__{
      type: :attack_outcome,
      target_guid: attacker_guid,
      source_guid: victim_guid,
      outcome: outcome,
      damage: damage,
      proc_damage: proc_damage || damage,
      spell_id: spell_id
    }
  end

  def attacker_state_update(source_guid, target_guid, damage, attack \\ %{})
      when is_integer(source_guid) and is_integer(target_guid) do
    %__MODULE__{
      type: :attacker_state_update,
      source_guid: source_guid,
      target_guid: target_guid,
      damage: damage,
      attack: attack
    }
  end

  def enqueue(entity, events) when is_list(events) do
    Enum.reduce(events, entity, &enqueue(&2, &1))
  end

  def enqueue(%{internal: %{events: events} = internal} = entity, %__MODULE__{} = event) when is_list(events) do
    %{entity | internal: %{internal | events: events ++ [event]}}
  end

  def enqueue(%{internal: internal} = entity, %__MODULE__{} = event) do
    %{entity | internal: %{internal | events: [event]}}
  end

  def enqueue(entity, _event), do: entity

  def teleport({_x, _y, _z, _o} = position) do
    %__MODULE__{type: :teleport, position: position}
  end

  def leap({_x, _y, _z, _o} = position) do
    %__MODULE__{type: :leap, position: position}
  end

  def teleport_to_spell_target(spell_id) when is_integer(spell_id) do
    %__MODULE__{type: :teleport_to_spell_target, spell_id: spell_id}
  end

  def refresh_party_aura(spell, radius) when is_number(radius) do
    %__MODULE__{type: :refresh_party_aura, spell: spell, amount: radius}
  end

  def redirect_damage(source_guid, target_guid, school, amount)
      when is_integer(target_guid) and is_integer(amount) and amount > 0 do
    %__MODULE__{
      type: :redirect_damage,
      source_guid: source_guid,
      target_guid: target_guid,
      school: school,
      amount: amount
    }
  end

  def consume_cast_item(item_guid) when is_integer(item_guid) do
    %__MODULE__{type: :consume_cast_item, cast_item_guid: item_guid}
  end

  def feed_pet(item_guid, pet_guid, trigger_spell_id, range_yards)
      when is_integer(item_guid) and is_integer(pet_guid) and is_integer(trigger_spell_id) do
    %__MODULE__{
      type: :feed_pet,
      cast_item_guid: item_guid,
      target_guid: pet_guid,
      spell_id: trigger_spell_id,
      range_yards: range_yards
    }
  end

  def enchant_item(item_guid, spell, effect) when is_integer(item_guid) do
    %__MODULE__{type: :enchant_item, target_guid: item_guid, spell: spell, effect: effect}
  end

  def open_gameobject(object_guid) when is_integer(object_guid) do
    %__MODULE__{type: :open_gameobject, target_guid: object_guid}
  end

  def create_item(item_id, count) when is_integer(item_id) and is_integer(count) do
    %__MODULE__{type: :create_item, item_id: item_id, count: count}
  end

  def create_item(target_guid, item_id, count)
      when is_integer(target_guid) and is_integer(item_id) and is_integer(count) do
    %__MODULE__{type: :create_item, target_guid: target_guid, item_id: item_id, count: count}
  end

  def spawn_area_effect(spell, effect, {_x, _y, _z} = position, duration_ms) when is_integer(duration_ms) do
    %__MODULE__{
      type: :spawn_area_effect,
      spell: spell,
      effect: effect,
      position: position,
      duration_ms: duration_ms
    }
  end

  def spawn_farsight(spell, {_x, _y, _z} = position, duration_ms) when is_integer(duration_ms) do
    %__MODULE__{type: :spawn_farsight, spell: spell, position: position, duration_ms: duration_ms}
  end

  def despawn_area_effects(spell_id) when is_integer(spell_id) do
    %__MODULE__{type: :despawn_area_effects, spell_id: spell_id}
  end

  def despawn_entity(guid) when is_integer(guid) do
    %__MODULE__{type: :despawn_entity, target_guid: guid}
  end

  def leave_ritual(game_object_guid, user_guid) when is_integer(game_object_guid) and is_integer(user_guid) do
    %__MODULE__{type: :leave_ritual, target_guid: game_object_guid, source_guid: user_guid}
  end

  def summon_game_object(entry, duration_ms, opts \\ []) when is_integer(entry) and is_integer(duration_ms) do
    %__MODULE__{
      type: :summon_game_object,
      entry: entry,
      duration_ms: duration_ms,
      target_guid: Keyword.get(opts, :ritual_target_guid)
    }
  end

  def summon_request(summoner_guid, target_guid, zone_id, {world, x, y, z})
      when is_integer(summoner_guid) and is_integer(target_guid) do
    %__MODULE__{
      type: :summon_request,
      source_guid: summoner_guid,
      target_guid: target_guid,
      amount: zone_id,
      position: {world, x, y, z}
    }
  end

  def consume_reagents(reagents) when is_list(reagents) do
    %__MODULE__{type: :consume_reagents, reagents: reagents}
  end

  def trigger_spell(source_guid, source_level, target_guid, spell_id, opts \\ [])
      when is_integer(target_guid) and is_integer(spell_id) do
    %__MODULE__{
      type: :trigger_spell,
      source_guid: source_guid,
      source_level: source_level,
      target_guid: target_guid,
      spell_id: spell_id,
      target_role: Keyword.get(opts, :target_role),
      triggering_spell_id: Keyword.get(opts, :triggered_by_spell_id),
      slot: Keyword.get(opts, :effect_index),
      amount: Keyword.get(opts, :base_points),
      resolve_targets?: Keyword.get(opts, :resolve_targets?, false)
    }
  end

  def monster_talk(text, chat_type, target_guid) when is_binary(text) and is_atom(chat_type) do
    %__MODULE__{type: :monster_talk, text: text, chat_type: chat_type, target_guid: target_guid}
  end

  def emote(emote_id) when is_integer(emote_id) do
    %__MODULE__{type: :emote, emote_id: emote_id}
  end

  def script_steps(steps, target_guid, delay_ms) when is_list(steps) and is_integer(delay_ms) do
    %__MODULE__{type: :script_steps, steps: steps, target_guid: target_guid, duration_ms: delay_ms}
  end

  def summon_creature(summon, steps, target_guid) when is_map(summon) and is_list(steps) do
    %__MODULE__{type: :summon_creature, summon: summon, steps: steps, target_guid: target_guid}
  end

  def control_granted(owner_guid, controlled_guid, spell_id, spells, opts \\ [])
      when is_integer(owner_guid) and is_integer(controlled_guid) and is_integer(spell_id) and is_list(spells) do
    %__MODULE__{
      type: :control_granted,
      source_guid: owner_guid,
      target_guid: controlled_guid,
      spell_id: spell_id,
      spells: spells,
      enabled?: Keyword.get(opts, :possess?, false)
    }
  end

  def control_released(owner_guid, controlled_guid) when is_integer(owner_guid) and is_integer(controlled_guid) do
    %__MODULE__{type: :control_released, source_guid: owner_guid, target_guid: controlled_guid}
  end

  def release_controlled(owner_guid, controlled_guid, spell_id)
      when is_integer(owner_guid) and is_integer(controlled_guid) and is_integer(spell_id) do
    %__MODULE__{
      type: :release_controlled,
      source_guid: owner_guid,
      target_guid: controlled_guid,
      spell_id: spell_id
    }
  end

  def viewpoint_granted(owner_guid, viewpoint_guid) when is_integer(owner_guid) and is_integer(viewpoint_guid) do
    %__MODULE__{type: :viewpoint_granted, source_guid: owner_guid, target_guid: viewpoint_guid}
  end

  def viewpoint_released(owner_guid, viewpoint_guid) when is_integer(owner_guid) and is_integer(viewpoint_guid) do
    %__MODULE__{type: :viewpoint_released, source_guid: owner_guid, target_guid: viewpoint_guid}
  end

  def summon_pet(owner_guid, entry, spell_id)
      when is_integer(owner_guid) and is_integer(entry) and entry > 0 and is_integer(spell_id) do
    %__MODULE__{type: :summon_pet, source_guid: owner_guid, entry: entry, spell_id: spell_id}
  end

  def tame_creature(owner_guid, entry) when is_integer(owner_guid) and is_integer(entry) and entry > 0 do
    %__MODULE__{type: :tame_creature, source_guid: owner_guid, entry: entry}
  end

  def dismiss_pet(owner_guid) when is_integer(owner_guid) do
    %__MODULE__{type: :dismiss_pet, source_guid: owner_guid}
  end

  def summon_totem(entry, slot, duration_ms)
      when is_integer(entry) and entry > 0 and slot in 1..4 and is_integer(duration_ms) do
    %__MODULE__{type: :summon_totem, entry: entry, slot: slot, duration_ms: duration_ms}
  end

  def despawn_self(despawn_delay_ms, respawn_delay_ms)
      when is_integer(despawn_delay_ms) and is_integer(respawn_delay_ms) do
    %__MODULE__{type: :despawn_self, duration_ms: despawn_delay_ms, respawn_delay_ms: respawn_delay_ms}
  end

  def attack_start(target_guid) when is_integer(target_guid) do
    %__MODULE__{type: :attack_start, target_guid: target_guid}
  end

  def forward_script_steps(target_guid, steps, source_guid) when is_integer(target_guid) and is_list(steps) do
    %__MODULE__{type: :forward_script_steps, target_guid: target_guid, steps: steps, source_guid: source_guid}
  end

  def play_sound(sound_id) when is_integer(sound_id) do
    %__MODULE__{type: :play_sound, sound_id: sound_id}
  end

  def play_object_sound(sound_id) when is_integer(sound_id) do
    %__MODULE__{type: :play_object_sound, sound_id: sound_id}
  end

  def set_facing({:angle, angle} = facing) when is_number(angle) do
    %__MODULE__{type: :set_facing, facing: facing}
  end

  def set_facing({:target, target_guid} = facing) when is_integer(target_guid) do
    %__MODULE__{type: :set_facing, facing: facing}
  end

  def drain(%{internal: %{events: events} = internal} = entity) when is_list(events) do
    {%{entity | internal: %{internal | events: []}}, events}
  end

  def drain(entity), do: {entity, []}
end
