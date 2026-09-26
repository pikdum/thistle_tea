defmodule ThistleTea.Game.Entity do
  @moduledoc """
  Boundary facade for talking to live entities by guid: registry lookups and
  casts to the owning process (movement, attacks, spells, update requests).
  """
  alias ThistleTea.Game.Entity.Data.SummonEvent
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.WorldRef

  def register(guid), do: EntityRegistry.register(guid)
  def unregister(guid), do: EntityRegistry.unregister(guid)
  def online?(guid), do: EntityRegistry.registered?(guid)

  def pid(target) do
    case resolve_pid(target) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  def request_update_from(entity, target \\ self()) do
    dispatch_cast(entity, {:send_update_to, target})
  end

  def move_to(entity, {x, y, z}) do
    dispatch_cast(entity, {:move_to, x, y, z})
  end

  def move_to(entity, {x, y, z}, opts) when is_list(opts) do
    dispatch_cast(entity, {:move_to, x, y, z, opts})
  end

  def aggro_probe(entity, target_guid) do
    dispatch_cast(entity, {:aggro_probe, target_guid})
  end

  def assist_attack(entity, target_guid) do
    dispatch_cast(entity, {:assist_attack, target_guid})
  end

  def assist_attack(entity, target_guid, source) do
    dispatch_cast(entity, {:assist_attack, target_guid, source})
  end

  def flee_from_help(entity, caller_guid, target_guid),
    do: dispatch_cast(entity, {:flee_from_help, caller_guid, target_guid})

  def receive_spell(entity, caster, spell) do
    dispatch_cast(entity, {:receive_spell, caster, spell})
  end

  def pvp_contact(entity, effect), do: dispatch_cast(entity, {:pvp_contact, effect})
  def instance_membership_changed(entity, world), do: dispatch_cast(entity, {:instance_membership_changed, world})
  def instance_lockout_changed(entity, reason), do: dispatch_cast(entity, {:instance_lockout_changed, reason})
  def sync_pvp(entity, owner, enabled), do: dispatch_cast(entity, {:sync_pvp, owner, enabled})
  def finish_movement(entity, controller, payload), do: dispatch_cast(entity, {:finish_movement, controller, payload})

  def sync_pet_spell_modifiers(entity, owner, holders) do
    dispatch_cast(entity, {:pet_spell_modifiers, owner, holders})
  end

  def spell_contact(entity, effect), do: dispatch_cast(entity, {:spell_contact, effect})

  def trigger_spell(entity, spell_id, target_guid, opts \\ []) do
    dispatch_cast(entity, {:trigger_spell, spell_id, target_guid, opts})
  end

  def remove_aura(entity, spell_id, caster_guid) do
    dispatch_cast(entity, {:remove_aura, spell_id, caster_guid})
  end

  def remove_area_aura(entity, area_guid) do
    dispatch_cast(entity, {:remove_area_aura, area_guid})
  end

  def remove_spell_auras(entity, spell_ids) when is_list(spell_ids) do
    dispatch_cast(entity, {:remove_spell_auras, spell_ids})
  end

  def monster_talk(entity, text, chat_type) when is_binary(text) and is_atom(chat_type) do
    dispatch_cast(entity, {:monster_talk, text, chat_type})
  end

  def modify_npc_flags(entity, flags, mode) when is_integer(flags) and mode in [:add, :remove] do
    dispatch_cast(entity, {:modify_npc_flags, flags, mode})
  end

  def modify_unit_flags(entity, flags, mode) when is_integer(flags) and mode in [:add, :remove] do
    dispatch_cast(entity, {:modify_unit_flags, flags, mode})
  end

  def operate_game_object(entity, action, reset_delay_ms \\ 0)
      when action in [:open, :close, :reset, :destroy] and is_integer(reset_delay_ms) do
    dispatch_cast(entity, {:operate_game_object, action, reset_delay_ms})
  end

  def hide_game_object(entity), do: dispatch_cast(entity, {:battleground_hide_game_object})
  def apply_game_object_action(entity, effect), do: dispatch_cast(entity, effect)
  def use_quest_object(entity, guid, world), do: dispatch_cast(entity, {:use_quest_object, guid, world})

  def battleground_resurrect(entity, position) do
    dispatch_cast(entity, {:battleground_resurrect, position})
  end

  def battleground_exit(entity, world, position) do
    dispatch_cast(entity, {:battleground_exit, world, position})
  end

  def battleground_deserted(entity), do: dispatch_cast(entity, :battleground_deserted)

  def reward_reputation(entity, faction_id, amount) do
    dispatch_cast(entity, {:battleground_reputation, faction_id, amount})
  end

  def teleport(entity, world, {x, y, z, orientation}) do
    dispatch_cast(entity, {:start_teleport, x, y, z, orientation, world})
  end

  def quest_kill_credit(entity, creature_entry) when is_integer(creature_entry) and creature_entry > 0 do
    dispatch_cast(entity, {:quest_kill_credit, creature_entry})
  end

  def delay_aura(entity, spell_id, caster_guid, delay_ms) do
    dispatch_cast(entity, {:delay_aura, spell_id, caster_guid, delay_ms})
  end

  def receive_attack(entity, attack) do
    dispatch_cast(entity, {:receive_attack, attack})
  end

  def receive_shared_damage(entity, effect), do: dispatch_cast(entity, {:receive_shared_damage, effect})

  def attack_outcome(entity, payload) do
    dispatch_cast(entity, {:attack_outcome, payload})
  end

  def advance_combat_skill(entity, skill_id) do
    dispatch_cast(entity, {:advance_combat_skill, skill_id})
  end

  def spell_outcome(entity, payload) do
    dispatch_cast(entity, {:spell_outcome, payload})
  end

  def drain_power(entity, power_type) do
    dispatch_cast(entity, {:drain_power, power_type})
  end

  def grant_power(entity, effect) do
    dispatch_cast(entity, {:grant_power, effect})
  end

  def leech_power(entity, effect), do: dispatch_cast(entity, {:leech_power, effect})

  def add_threat(entity, effect), do: dispatch_cast(entity, {:add_threat, effect})

  def add_combo_points(entity, award) do
    dispatch_cast(entity, {:add_combo_points, award})
  end

  def receive_heal(entity, amount) do
    dispatch_cast(entity, {:receive_heal, amount})
  end

  def heal_threat(entity, healer_guid, healed_guid, amount) do
    dispatch_cast(entity, {:heal_threat, healer_guid, healed_guid, amount})
  end

  def threat_ref_gained(entity, mob_guid, incarnation_id) do
    dispatch_cast(entity, {:threat_ref_gained, mob_guid, incarnation_id})
  end

  def threat_ref_lost(entity, mob_guid, incarnation_id) do
    dispatch_cast(entity, {:threat_ref_lost, mob_guid, incarnation_id})
  end

  def drop_threat(entity, source_guid) do
    dispatch_cast(entity, {:drop_threat, source_guid})
  end

  def feign_death_target_lost(entity, source_guid) do
    dispatch_cast(entity, {:feign_death_target_lost, source_guid})
  end

  def temporary_threat(entity, source_guid, incarnation_id, amount) do
    dispatch_cast(entity, {:temporary_threat, source_guid, incarnation_id, amount})
  end

  def use_game_object(entity, user_guid, user_level) do
    dispatch_cast(entity, {:gameobject_use, user_guid, user_level})
  end

  def request_summon(entity, summoner_guid, area, world, position) do
    dispatch_cast(entity, {:summon_request, summoner_guid, area, world, position})
  end

  def offer_quest(entity, sharer_guid, quest_id, mode) do
    dispatch_cast(entity, {:quest_share, sharer_guid, quest_id, mode})
  end

  def cancel_quest_share(entity, sharer_guid, quest_id) do
    dispatch_cast(entity, {:cancel_quest_share, sharer_guid, quest_id})
  end

  def start_game_object_channel(entity, game_object_guid, spell, duration_ms) do
    dispatch_cast(entity, {:start_game_object_channel, game_object_guid, spell, duration_ms})
  end

  def finish_game_object_channel(entity, game_object_guid) do
    dispatch_cast(entity, {:finish_game_object_channel, game_object_guid})
  end

  def leave_ritual(entity, user_guid) do
    dispatch_cast(entity, {:ritual_user_left, user_guid})
  end

  def reward_kill(entity, victim) do
    dispatch_cast(entity, {:reward_kill, victim})
  end

  def reward_kill_share(entity, victim, award) do
    dispatch_cast(entity, {:reward_kill_share, victim, award})
  end

  def start_script(entity, steps, target_guid) when is_list(steps) and is_integer(target_guid) do
    dispatch_cast(entity, {:start_script, steps, target_guid})
  end

  def start_script(entity, steps, target_guid, %WorldRef{} = world) when is_list(steps) and is_integer(target_guid) do
    dispatch_cast(entity, {:start_script, steps, target_guid, world})
  end

  def script_event(entity, event_id, data, invoker_guid \\ nil)
      when is_integer(event_id) and is_integer(data) and (is_integer(invoker_guid) or is_nil(invoker_guid)) do
    dispatch_cast(entity, {:script_event, event_id, data, invoker_guid})
  end

  def receive_emote(entity, player_guid, emote_id) when is_integer(player_guid) and is_integer(emote_id) do
    dispatch_cast(entity, {:receive_emote, player_guid, emote_id})
  end

  def spell_hit_target(entity, target_guid, spell) when is_integer(target_guid) do
    dispatch_cast(entity, {:spell_hit_target, target_guid, spell})
  end

  def summon_event(entity, %SummonEvent{} = event), do: dispatch_cast(entity, event)

  def enter_evade(entity), do: dispatch_cast(entity, :enter_evade)

  def loot_roll_vote(entity, voter_guid, slot, vote) do
    dispatch_cast(entity, {:loot_roll_vote, voter_guid, slot, vote})
  end

  def loot_reservation_result(entity, %Commit{} = result), do: dispatch_cast(entity, result)
  def loot_reservation_result(entity, %Release{} = result), do: dispatch_cast(entity, result)

  def receive_money(entity, amount) do
    dispatch_cast(entity, {:receive_money, amount})
  end

  def destroy_object(entity, guid) do
    dispatch_cast(entity, {:destroy_object, guid})
  end

  def visibility_changed(entity, guid) do
    dispatch_cast(entity, {:visibility_changed, guid})
  end

  def set_speed(entity, rate) do
    dispatch_cast(entity, {:set_speed, rate})
  end

  def board_transport(entity, player_guid, world, local_position) do
    call(entity, {:transport_board, player_guid, world, local_position})
  end

  def transport_update(entity) do
    call(entity, :transport_update)
  end

  def leave_transport(entity, player_guid) do
    dispatch_cast(entity, {:transport_leave, player_guid})
  end

  def duel_update(entity, update) do
    dispatch_cast(entity, {:duel_update, update})
  end

  def call(entity, message) do
    case resolve_pid(entity) do
      {:ok, pid} -> GenServer.call(pid, message)
      error -> error
    end
  catch
    :exit, _ -> {:error, :not_found}
  end

  def remove_insignia(entity, looter_guid, death_id),
    do: dispatch_cast(entity, {:remove_insignia, looter_guid, death_id})

  def insignia_loot(entity, bones_guid), do: dispatch_cast(entity, {:insignia_loot, bones_guid})

  defp dispatch_cast(target, message) do
    case resolve_pid(target) do
      {:ok, pid} -> GenServer.cast(pid, message)
      error -> error
    end
  end

  defp resolve_pid(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_pid(guid) when is_integer(guid) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :not_found}
    end
  end

  defp resolve_pid(_target), do: {:error, :invalid_target}
end
