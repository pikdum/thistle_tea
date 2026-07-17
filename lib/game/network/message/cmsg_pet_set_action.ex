defmodule ThistleTea.Game.Network.Message.CmsgPetSetAction do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_SET_ACTION

  alias ThistleTea.Game.Entity

  defstruct [:pet_guid, actions: []]

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: pet_guid, actions: actions}, %{character: %Character{} = character} = state) do
    if Character.controls?(character, pet_guid) do
      case Entity.pid(pet_guid) do
        pid when is_pid(pid) -> send(pid, {:pet_set_actions, actions})
        _ -> :ok
      end
    end

    state
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(
        <<pet_guid::little-size(64), position1::little-size(32), data1::little-size(32), position2::little-size(32),
          data2::little-size(32)>>
      ) do
    %__MODULE__{pet_guid: pet_guid, actions: [action(position1, data1), action(position2, data2)]}
  end

  def from_binary(<<pet_guid::little-size(64), position::little-size(32), data::little-size(32)>>) do
    %__MODULE__{pet_guid: pet_guid, actions: [action(position, data)]}
  end

  defp action(position, data) do
    %{position: position, action: Bitwise.band(data, 0x00FFFFFF), action_type: Bitwise.bsr(data, 24)}
  end
end
