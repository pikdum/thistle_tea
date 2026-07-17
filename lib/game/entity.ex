defmodule ThistleTea.Game.Entity do
  @moduledoc """
  Boundary facade for talking to live entities by guid: registry lookups and
  casts to the owning process (movement, attacks, spells, update requests).
  """
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry

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

  def aggro_probe(entity, target_guid) do
    dispatch_cast(entity, {:aggro_probe, target_guid})
  end

  def receive_spell(entity, caster, spell) do
    dispatch_cast(entity, {:receive_spell, caster, spell})
  end

  def remove_aura(entity, spell_id, caster_guid) do
    dispatch_cast(entity, {:remove_aura, spell_id, caster_guid})
  end

  def receive_attack(entity, attack) do
    dispatch_cast(entity, {:receive_attack, attack})
  end

  def attack_outcome(entity, payload) do
    dispatch_cast(entity, {:attack_outcome, payload})
  end

  def drain_power(entity, power_type) do
    dispatch_cast(entity, {:drain_power, power_type})
  end

  def grant_power(entity, power_type, amount) do
    dispatch_cast(entity, {:grant_power, power_type, amount})
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

  def use_game_object(entity, user_guid, user_level) do
    dispatch_cast(entity, {:gameobject_use, user_guid, user_level})
  end

  def request_summon(entity, summoner_guid, area, world, position) do
    dispatch_cast(entity, {:summon_request, summoner_guid, area, world, position})
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

  def reward_kill_share(entity, victim, xp) do
    dispatch_cast(entity, {:reward_kill_share, victim, xp})
  end

  def loot_roll_vote(entity, voter_guid, slot, vote) do
    dispatch_cast(entity, {:loot_roll_vote, voter_guid, slot, vote})
  end

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

  def call(entity, message) do
    case resolve_pid(entity) do
      {:ok, pid} -> GenServer.call(pid, message)
      error -> error
    end
  catch
    :exit, _ -> {:error, :not_found}
  end

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
