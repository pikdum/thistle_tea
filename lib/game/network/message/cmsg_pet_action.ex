defmodule ThistleTea.Game.Network.Message.CmsgPetAction do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_ACTION

  import Bitwise, only: [&&&: 2, >>>: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Hostility

  @act_command 0x07
  @act_reaction 0x06

  defstruct [:pet_guid, :action, :action_type, :target_guid]

  @impl ClientMessage
  def handle(
        %__MODULE__{pet_guid: pet_guid} = message,
        %{character: %Character{unit: %Unit{summon: pet_guid}} = character} = state
      ) do
    if valid_action?(character, message) do
      case Entity.pid(pet_guid) do
        pid when is_pid(pid) -> dispatch(pid, message)
        _ -> :ok
      end
    end

    state
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<pet_guid::little-size(64), data::little-size(32), target_guid::little-size(64)>>) do
    %__MODULE__{
      pet_guid: pet_guid,
      action: data &&& 0x00FFFFFF,
      action_type: data >>> 24,
      target_guid: target_guid
    }
  end

  defp dispatch(pid, %__MODULE__{action_type: @act_command, action: action, target_guid: target_guid}) do
    send(pid, {:pet_command, command(action), target_guid})
  end

  defp dispatch(pid, %__MODULE__{action_type: @act_reaction, action: action}) do
    send(pid, {:pet_reaction, reaction(action)})
  end

  defp dispatch(pid, %__MODULE__{action: spell_id, target_guid: target_guid}) when spell_id > 0 do
    send(pid, {:pet_cast, spell_id, target_guid})
  end

  defp dispatch(_pid, _message), do: :ok

  defp valid_action?(character, %__MODULE__{action_type: @act_command, action: 2, target_guid: target_guid}) do
    Hostility.valid_attack_target?(character, target_guid)
  end

  defp valid_action?(_character, _message), do: true

  defp command(0), do: :stay
  defp command(1), do: :follow
  defp command(2), do: :attack
  defp command(3), do: :dismiss
  defp command(_), do: :unknown

  defp reaction(0), do: :passive
  defp reaction(1), do: :defensive
  defp reaction(2), do: :aggressive
  defp reaction(_), do: :defensive
end
