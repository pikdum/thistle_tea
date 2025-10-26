defmodule ThistleTea.Game.Message.CmsgAttackswing do
  use ThistleTea.Game.ClientMessage, :CMSG_ATTACKSWING
  use ThistleTea.Opcodes, [:SMSG_ATTACKSTART, :SMSG_ATTACKSTOP]

  alias ThistleTea.Game.Message

  require Logger

  defstruct [:target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{target_guid: target_guid}, state) do
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

    Map.merge(state, %{attacking: target_guid, attack_timer: attack_timer})
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<target_guid::little-size(64)>> = payload

    %__MODULE__{
      target_guid: target_guid
    }
  end

  def handle_attack_swing(state) do
    case Map.fetch(state, :attacking) do
      {:ok, target_guid} ->
        weapon = state.character.equipment.mainhand
        %{dmg_min1: min_damage, dmg_max1: max_damage, delay: attack_speed} = weapon

        pid = :ets.lookup_element(:entities, target_guid, 2)
        attack = %{caster: state.guid, min_damage: min_damage, max_damage: max_damage}
        GenServer.cast(pid, {:receive_attack, attack})
        attack_timer = Process.send_after(self(), :attack_swing, attack_speed)
        Map.put(state, :attack_timer, attack_timer)

      :error ->
        state |> Map.delete(:attack_timer)
    end
  end
end
