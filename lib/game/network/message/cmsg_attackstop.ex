defmodule ThistleTea.Game.Network.Message.CmsgAttackstop do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSTOP

  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network.PlayerTick

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{character: %Character{unit: unit} = character} = state) do
    target_guid = unit.target

    if is_integer(target_guid) and target_guid > 0 do
      Logger.info("CMSG_ATTACKSTOP: #{target_guid}")

      %Message.SmsgAttackstop{
        player: state.guid,
        enemy: target_guid
      }
      |> World.broadcast_packet(character)
    end

    character =
      character
      |> BT.clear_auto_attack()
      |> Ranged.stop()
      |> clear_target()

    Core.update_object(character, :values)
    |> World.broadcast_packet(character)

    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    state
    |> Map.put(:character, character)
    |> Map.put(:player_tick_ref, nil)
    |> PlayerTick.ensure_scheduled()
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  defp clear_target(%Character{unit: unit} = character) do
    %{character | unit: %{unit | target: 0}}
  end
end
