defmodule ThistleTea.Game.Network.Message.CmsgStandstatechange do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_STANDSTATECHANGE

  defstruct [:animation_state]

  @impl ClientMessage
  def handle(
        %__MODULE__{animation_state: animation_state},
        %{character: %Character{unit: %Unit{} = unit} = character} = state
      ) do
    character = %{character | unit: %{unit | stand_state: animation_state}}

    %UpdateObject{update_type: :values, object_type: :player}
    |> struct(Map.from_struct(character))
    |> UpdateObject.to_packet()
    |> World.broadcast_packet(character, include_self?: false)

    # TODO: for some reason players are stuck sitting
    %{state | character: character}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<animation_state::little-size(32)>> = payload

    %__MODULE__{
      animation_state: animation_state
    }
  end
end
