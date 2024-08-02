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

    {:continue, Map.put(state, :attacking, target_guid)}
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
end
