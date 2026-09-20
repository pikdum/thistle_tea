defmodule ThistleTea.Game.Entity.Logic.Pvp do
  @moduledoc """
  Pure world-PvP transitions and projection of player and unit flags.
  Countdown time is spent only while the relevant PvP restrictions are absent.
  """

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Pvp
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Dueling

  @pvp_duration_ms 300_000
  @contested_duration_ms 30_000
  @unit_pvp 0x00001000
  @player_ffa 0x00000080
  @player_contested 0x00000100
  @player_desired 0x00000200
  @capital 0x100
  @arena 0x80

  def toggle(%Character{} = character, desired, now) when desired in [true, false, :toggle] do
    character = tick(character, now)
    pvp = character.internal.pvp
    desired = if desired == :toggle, do: not pvp.desired?, else: desired
    pvp = %{pvp | desired?: desired}
    pvp = if desired, do: %{pvp | remaining_ms: @pvp_duration_ms}, else: pvp
    put(character, pvp)
  end

  def territory(%Character{} = character, zone, area, realm, battleground?, now) do
    character = tick(character, now)
    pvp = character.internal.pvp
    enforced? = enforced?(character.unit.race, zone, realm, battleground?)
    free_for_all? = flag?(area, @arena)
    pvp = %{pvp | enforced?: enforced?, free_for_all?: free_for_all?}

    pvp =
      if enforced? and is_nil(character.internal.taxi_flight),
        do: %{pvp | remaining_ms: @pvp_duration_ms},
        else: pvp

    put(character, pvp)
  end

  def contact(%Character{} = character, role, other, now) when role in [:attack, :attacked, :assist] do
    character = tick(character, now)

    if flags_contact?(character, role, other) do
      pvp = character.internal.pvp
      combat? = role != :assist or Map.get(other, :in_combat, false)
      contested? = (role == :attack and is_integer(other.player_guid)) or (role == :assist and other.contested_pvp?)

      pvp = %{
        pvp
        | remaining_ms: @pvp_duration_ms,
          combat?: pvp.combat? or combat?,
          contested_remaining_ms: if(contested?, do: @contested_duration_ms, else: pvp.contested_remaining_ms)
      }

      put(character, pvp)
    else
      character
    end
  end

  def contact(entity, _role, _other, _now), do: entity

  def tick(%Character{} = character, now) when is_integer(now) do
    pvp = character.internal.pvp
    elapsed = if is_integer(pvp.updated_at), do: max(now - pvp.updated_at, 0), else: 0
    combat? = pvp.combat? and character.internal.in_combat == true and not Core.dead?(character)
    paused? = combat? or pvp.desired? or pvp.enforced?

    pvp = %{
      pvp
      | updated_at: now,
        combat?: combat?,
        remaining_ms: countdown(pvp.remaining_ms, elapsed, paused?),
        contested_remaining_ms: countdown(pvp.contested_remaining_ms, elapsed, combat?)
    }

    put(character, pvp)
  end

  def tick(entity, _now), do: entity

  def reconnect(%Character{} = character, now) do
    put(character, %{character.internal.pvp | updated_at: now, combat?: false})
  end

  def active?(%Character{internal: %{pvp: %Pvp{remaining_ms: remaining}}}), do: remaining > 0
  def active?(%{unit: %{flags: flags}}), do: active_flags?(flags)
  def active?(%{unit_flags: flags}), do: active_flags?(flags)
  def active?(_entity), do: false

  def free_for_all?(%Character{internal: %{pvp: %Pvp{free_for_all?: enabled}}}), do: enabled
  def free_for_all?(%{free_for_all?: enabled}), do: enabled
  def free_for_all?(_entity), do: false

  def contested?(%Character{internal: %{pvp: %Pvp{contested_remaining_ms: remaining}}}), do: remaining > 0
  def contested?(_entity), do: false

  def needs_tick?(%Character{internal: %{pvp: %Pvp{} = pvp}}) do
    pvp.remaining_ms > 0 or pvp.contested_remaining_ms > 0
  end

  def needs_tick?(_entity), do: false

  def unit_flags(flags, enabled), do: set_flag(flags, @unit_pvp, enabled)

  defp flags_contact?(character, role, %{pvp?: true, player_guid: player_guid} = other) do
    own_guid = character.object.guid

    cond do
      player_guid == own_guid -> false
      duel_opponent?(character, player_guid) -> false
      arena_opponents?(character, other) -> false
      role == :attacked -> is_integer(player_guid)
      role == :assist -> is_integer(player_guid) or Map.get(other, :in_combat, false)
      true -> true
    end
  end

  defp flags_contact?(_character, _role, _other), do: false

  defp duel_opponent?(character, player_guid) do
    Dueling.active?(character) and Dueling.opponent_guid(character) == player_guid
  end

  defp arena_opponents?(character, other) do
    free_for_all?(character) and Map.get(other, :free_for_all?, false)
  end

  defp enforced?(_race, _zone, _realm, true), do: true

  defp enforced?(race, %{faction_group: team} = zone, realm, false) do
    case team do
      2 -> race not in [1, 3, 4, 7] and (realm == :pvp or flag?(zone, @capital))
      4 -> race not in [2, 5, 6, 8] and (realm == :pvp or flag?(zone, @capital))
      0 -> realm == :pvp
      _ -> false
    end
  end

  defp enforced?(_race, _zone, _realm, _battleground?), do: false

  defp flag?(%{flags: flags}, mask) when is_integer(flags), do: (flags &&& mask) != 0
  defp flag?(_area, _mask), do: false

  defp countdown(remaining, _elapsed, true), do: remaining
  defp countdown(remaining, elapsed, false), do: max(remaining - elapsed, 0)

  defp active_flags?(flags) when is_integer(flags), do: (flags &&& @unit_pvp) != 0
  defp active_flags?(_flags), do: false

  defp put(%Character{} = character, %Pvp{} = pvp) do
    unit = %{character.unit | flags: unit_flags(character.unit.flags, pvp.remaining_ms > 0)}

    flags =
      character.player.flags
      |> set_flag(@player_desired, pvp.desired?)
      |> set_flag(@player_contested, pvp.contested_remaining_ms > 0)
      |> set_flag(@player_ffa, pvp.free_for_all?)

    updated = %{
      character
      | internal: %{character.internal | pvp: pvp},
        unit: unit,
        player: %{character.player | flags: flags}
    }

    if unit.flags != character.unit.flags or flags != character.player.flags,
      do: Core.mark_broadcast_update(updated),
      else: updated
  end

  defp set_flag(flags, mask, true), do: (flags || 0) ||| mask
  defp set_flag(flags, mask, false), do: (flags || 0) &&& bnot(mask)
end
