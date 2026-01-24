defmodule ThistleTea.Game.Network.Message.CmsgAttackswing do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSWING

  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.SpatialHash

  require Logger

  defstruct [:target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{target_guid: target_guid}, %{character: character} = state) do
    Logger.info("CMSG_ATTACKSWING: #{target_guid}")

    if valid_attack_target?(state, target_guid) do
      character =
        character
        |> maybe_reset_attack_started(target_guid)
        |> engage_combat(target_guid)

      Core.update_packet(character, :values)
      |> World.broadcast_packet(character)

      state
      |> Map.put(:character, character)
      |> ensure_player_tick()
    else
      send_attack_stop(state, target_guid)
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<target_guid::little-size(64)>> = payload

    %__MODULE__{
      target_guid: target_guid
    }
  end

  def handle_attack_swing(state), do: state

  defp maybe_reset_attack_started(%ThistleTea.Character{unit: %Unit{target: target}} = character, target_guid)
       when is_integer(target_guid) do
    if target == target_guid do
      character
    else
      BT.reset_attack_started(character)
    end
  end

  defp maybe_reset_attack_started(character, _target_guid), do: character

  defp valid_attack_target?(%{guid: guid, character: %ThistleTea.Character{internal: %{map: map}}}, target_guid)
       when is_integer(target_guid) and target_guid > 0 do
    target_guid != guid and
      match?({^target_guid, ^map, _x, _y, _z}, SpatialHash.get_entity(target_guid)) and
      unit_target?(target_guid)
  end

  defp valid_attack_target?(_state, _target_guid), do: false

  defp unit_target?(target_guid) when is_integer(target_guid) do
    :ets.match(:players, {:"$1", target_guid}) != [] or
      :ets.match(:mobs, {:"$1", target_guid}) != []
  end

  defp unit_target?(_target_guid), do: false

  defp send_attack_stop(%{guid: guid} = state, target_guid) when is_integer(guid) do
    enemy = if is_integer(target_guid) and target_guid > 0, do: target_guid, else: 0
    Network.send_packet(%Message.SmsgAttackstop{player: guid, enemy: enemy})
    state
  end

  defp send_attack_stop(state, _target_guid), do: state

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
