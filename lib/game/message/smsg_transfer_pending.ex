defmodule ThistleTea.Game.Message.SmsgTransferPending do
  use ThistleTea.Game.ServerMessage, :SMSG_TRANSFER_PENDING

  defstruct [
    :map,
    :has_transport,
    :transport,
    :transport_map
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map, has_transport: has_transport, transport: transport, transport_map: transport_map}) do
    <<map::little-size(32)>> <>
      if has_transport do
        <<transport::little-size(32), transport_map::little-size(32)>>
      else
        <<>>
      end
  end
end
