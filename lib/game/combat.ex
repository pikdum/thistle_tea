defmodule ThistleTea.Game.Combat do
  import ThistleTea.Character, only: [get_update_fields: 1]
  import ThistleTea.Game.UpdateObject, only: [generate_packet: 2]
  import ThistleTea.Util, only: [pack_guid: 1]

  require Logger

  @cmsg_attackswing 0x141
  @cmsg_attackstop 0x142
  @cmsg_setsheathed 0x1E0

  @smsg_attackstart 0x143
  @smsg_attackstop 0x144

  @update_type_values 0

  def handle_packet(@cmsg_attackswing, body, state) do
    <<target_guid::little-size(64)>> = body
    Logger.info("CMSG_ATTACKSWING: #{target_guid}")
    payload = <<state.guid::little-size(64), target_guid::little-size(64)>>

    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_packet, @smsg_attackstart, payload})
    end

    # TODO: safer way to get this
    attack_speed = state.character.equipment.mainhand.delay

    # use existing timer if already attacking
    attack_timer =
      case Map.fetch(state, :attack_timer) do
        {:ok, timer} -> timer
        :error -> Process.send_after(self(), :attack_swing, attack_speed)
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
        weapon = state.character.equipment.mainhand
        %{dmg_min1: min_damage, dmg_max1: max_damage, delay: attack_speed} = weapon

        with pid <- :ets.lookup_element(:locations, target_guid, 2) do
          attack = %{caster: state.guid, min_damage: min_damage, max_damage: max_damage}
          GenServer.cast(pid, {:receive_attack, attack})
        end

        attack_timer = Process.send_after(self(), :attack_swing, attack_speed)
        Map.put(state, :attack_timer, attack_timer)

      :error ->
        state |> Map.delete(:attack_timer)
    end
  end
end
