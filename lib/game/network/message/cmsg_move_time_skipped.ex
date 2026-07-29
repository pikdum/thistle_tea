defmodule ThistleTea.Game.Network.Message.CmsgMoveTimeSkipped do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_MOVE_TIME_SKIPPED
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_TIME_SKIPPED]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Packet

  @timestamp_modulus 0x1_0000_0000

  defstruct [:guid, :lag]

  @impl ClientMessage
  def handle(
        %__MODULE__{guid: guid, lag: lag},
        %State{
          guid: guid,
          transport_refresh_pending: transport_guid,
          character: %Character{movement_block: %MovementBlock{transport_guid: transport_guid} = movement_block}
        } = state
      )
      when is_integer(transport_guid) and is_integer(lag) do
    movement_block = advance_timestamp(movement_block, lag)
    Network.send_packet(UpdateObject.out_of_range([transport_guid]))
    send_transport_refresh(transport_guid)

    %{
      state
      | character: %{state.character | movement_block: movement_block},
        transport_refresh_pending: nil
    }
  end

  def handle(%__MODULE__{guid: guid, lag: lag}, %State{guid: guid, character: %Character{} = character} = state)
      when is_integer(lag) do
    movement_block = advance_timestamp(character.movement_block, lag)
    broadcast_time_skip(%{state | character: %{character | movement_block: movement_block}}, lag)
    %{state | character: %{character | movement_block: movement_block}}
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), lag::little-size(32)>> = payload

    %__MODULE__{
      guid: guid,
      lag: lag
    }
  end

  defp advance_timestamp(%MovementBlock{timestamp: timestamp} = movement_block, lag)
       when is_integer(timestamp) and timestamp > 0 do
    %{movement_block | timestamp: Integer.mod(timestamp + lag, @timestamp_modulus)}
  end

  defp advance_timestamp(%MovementBlock{} = movement_block, _lag), do: movement_block

  defp broadcast_time_skip(%State{guid: guid, character: %Character{} = character} = state, lag) do
    guid
    |> BinaryUtils.pack_guid()
    |> Kernel.<>(<<lag::little-size(32)>>)
    |> Packet.build(@msg_move_time_skipped)
    |> World.broadcast_packet(character, include_self?: false, recipients: state.player_guids)
  end

  defp send_transport_refresh(transport_guid) do
    case Entity.transport_update(transport_guid) do
      {:ok, %UpdateObject{} = update} ->
        Network.send_packet(%{update | has_transport: false})

      _error ->
        :ok
    end
  end
end
