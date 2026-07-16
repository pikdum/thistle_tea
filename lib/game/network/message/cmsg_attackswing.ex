defmodule ThistleTea.Game.Network.Message.CmsgAttackswing do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSWING

  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Network.PlayerTick
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
        |> set_attack_target(target_guid)
        |> BT.enable_auto_attack()

      Core.update_object(character, :values)
      |> World.broadcast_packet(character)

      state
      |> Map.put(:character, character)
      |> PlayerTick.schedule_now()
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

  defp maybe_reset_attack_started(%Character{unit: %Unit{target: target}} = character, target_guid)
       when is_integer(target_guid) do
    if target == target_guid do
      character
    else
      BT.reset_attack_started(character)
    end
  end

  defp maybe_reset_attack_started(character, _target_guid), do: character

  defp valid_attack_target?(%{guid: guid, character: %Character{internal: %{world: world}} = character}, target_guid)
       when is_integer(target_guid) and target_guid > 0 do
    target_guid != guid and
      match?({^target_guid, ^world, _x, _y, _z}, SpatialHash.get_entity(target_guid)) and
      unit_target?(target_guid) and
      Hostility.attackable?(character, target_guid)
  end

  defp valid_attack_target?(_state, _target_guid), do: false

  defp unit_target?(target_guid) when is_integer(target_guid) do
    :ets.match(:players, {:"$1", target_guid}) != [] or
      :ets.match(:mobs, {:"$1", target_guid}) != []
  end

  defp send_attack_stop(%{guid: guid} = state, target_guid) when is_integer(guid) do
    enemy = if is_integer(target_guid) and target_guid > 0, do: target_guid, else: 0
    Network.send_packet(%Message.SmsgAttackstop{player: guid, enemy: enemy})
    state
  end

  defp send_attack_stop(state, _target_guid), do: state

  defp set_attack_target(%Character{unit: unit} = character, target_guid) when is_integer(target_guid) do
    %{character | unit: %{unit | target: target_guid}}
  end

  defp set_attack_target(character, _target_guid), do: character
end
