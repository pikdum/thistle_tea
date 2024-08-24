defmodule ThistleTea.Game.Combat do
  import ThistleTea.Character, only: [get_update_fields: 1]
  import ThistleTea.Game.UpdateObject, only: [generate_packet: 2]
  import ThistleTea.Util, only: [pack_guid: 1, random_int: 2]

  require Logger

  @cmsg_attackswing 0x141
  @cmsg_attackstop 0x142
  @cmsg_setsheathed 0x1E0

  @smsg_attackstart 0x143
  @smsg_attackstop 0x144
  @smsg_attackerstateupdate 0x14A

  # TODO: hardcoded for now
  @attack_speed 1_000

  @update_type_values 0

  def handle_packet(@cmsg_attackswing, body, state) do
    <<target_guid::little-size(64)>> = body
    Logger.info("CMSG_ATTACKSWING: #{target_guid}")
    payload = <<state.guid::little-size(64), target_guid::little-size(64)>>

    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_packet, @smsg_attackstart, payload})
    end

    # use existing timer if already attacking
    attack_timer =
      case Map.fetch(state, :attack_timer) do
        {:ok, timer} -> timer
        :error -> Process.send_after(self(), :attack_swing, @attack_speed)
      end

    {:continue, Map.merge(state, %{attacking: target_guid, attack_timer: attack_timer})}
  end

  def handle_packet(@cmsg_attackstop, _body, state) do
    case Map.fetch(state, :attacking) do
      {:ok, target_guid} ->
        payload =
          state.packed_guid <>
            pack_guid(target_guid) <>
            <<0::little-size(32)>>

        Logger.info("CMSG_ATTACKSTOP: #{target_guid}")

        for pid <- Map.get(state, :player_pids, []) do
          GenServer.cast(pid, {:send_packet, @smsg_attackstop, payload})
        end

        {:continue, Map.delete(state, :attacking)}

      :error ->
        {:continue, state}
    end
  end

  def handle_packet(@cmsg_setsheathed, body, state) do
    Logger.info("CMSG_SETSHEATHED")
    <<sheath_state::little-size(32)>> = body
    character = Map.put(state.character, :sheath_state, sheath_state)
    fields = get_update_fields(character)
    packet = generate_packet(@update_type_values, fields)

    # TODO: this doesn't show the unsheathing animation
    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_update_packet, packet})
    end

    {:continue, Map.put(state, :character, character)}
  end

  def handle_attack_swing(state) do
    case Map.fetch(state, :attacking) do
      {:ok, target_guid} ->
        # normal_swing + affects_victim
        hit_info = 0x2

        # TODO: actual damage calculation + attack speed
        damage = random_int(1, 50)
        # TODO: showing fist animation instead of equipped weapon animation
        # TODO: do damage to target
        # TODO: range check, etc.
        payload =
          <<hit_info::little-size(32)>> <>
            state.packed_guid <>
            pack_guid(target_guid) <>
            <<
              # damage
              damage::little-size(32),
              # amount_of_damages
              1::little-size(8),
              # damage_state
              0::little-size(32),
              # unknown1
              0::little-size(32),
              # spell_id,
              0::little-size(32),
              # blocked_amount,
              0::little-size(32)
            >>

        for pid <- Map.get(state, :player_pids, []) do
          GenServer.cast(pid, {:send_packet, @smsg_attackerstateupdate, payload})
        end

        # TODO: come up with an abstraction for this + simplify
        ThistleTea.UnitRegistry
        |> Registry.dispatch(target_guid, fn entries ->
          for {pid, _} <- entries do
            GenServer.cast(pid, {:receive_attack, state.guid, damage})
          end
        end)

        attack_timer = Process.send_after(self(), :attack_swing, @attack_speed)
        Map.put(state, :attack_timer, attack_timer)

      :error ->
        state |> Map.delete(:attack_timer)
    end
  end
end
