defmodule ThistleTea.Game.Network.Message.CmsgAttackstop do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSTOP

  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Core

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{character: %ThistleTea.Character{unit: unit} = character} = state) do
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
      |> BT.reset_attack_started()
      |> clear_combat()

    Core.update_packet(character, :values)
    |> World.broadcast_packet(character)

    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    state
    |> Map.put(:character, character)
    |> Map.put(:player_tick_ref, nil)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  defp clear_combat(%ThistleTea.Character{unit: unit, internal: internal} = character) do
    unit = %{unit | target: 0}
    internal = %{internal | in_combat: false}
    %{character | unit: unit, internal: internal}
  end

  defp clear_combat(character), do: character
end
