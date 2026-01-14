defmodule ThistleTea.Game.Network.Message.CmsgAttackswing do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSWING

  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Time

  require Logger

  defstruct [:target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{target_guid: target_guid}, %{character: character} = state) do
    Logger.info("CMSG_ATTACKSWING: #{target_guid}")

    character =
      character
      |> BT.interrupt()
      |> engage_combat(target_guid)

    Core.update_packet(character, :values)
    |> World.broadcast_packet(character)

    state
    |> Map.put(:character, character)
    |> ensure_player_tick()
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<target_guid::little-size(64)>> = payload

    %__MODULE__{
      target_guid: target_guid
    }
  end

  def handle_attack_swing(state), do: state

  defp engage_combat(%ThistleTea.Character{unit: unit, internal: internal} = character, target_guid)
       when is_integer(target_guid) do
    now = Time.now()
    unit = %{unit | target: target_guid}
    internal = %{internal | in_combat: true, last_hostile_time: now}
    %{character | unit: unit, internal: internal}
  end

  defp engage_combat(character, _target_guid), do: character

  defp ensure_player_tick(state) do
    case Map.get(state, :player_tick_ref) do
      nil ->
        ref = Process.send_after(self(), :player_tick, 0)
        Map.put(state, :player_tick_ref, ref)

      ref ->
        Process.cancel_timer(ref)
        new_ref = Process.send_after(self(), :player_tick, 0)
        Map.put(state, :player_tick_ref, new_ref)
    end
  end
end
