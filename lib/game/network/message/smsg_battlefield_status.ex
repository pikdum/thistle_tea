defmodule ThistleTea.Game.Network.Message.SmsgBattlefieldStatus do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BATTLEFIELD_STATUS

  defstruct queue_slot: 0,
            map: 0,
            bracket: 0,
            client_instance_id: 0,
            status: :none,
            time_one_ms: 0,
            time_two_ms: 0

  @status %{none: 0, wait_queue: 1, wait_join: 2, in_progress: 3}

  @impl ServerMessage
  def to_binary(%__MODULE__{status: :none} = message) do
    <<message.queue_slot::little-size(32), 0::little-size(32)>>
  end

  def to_binary(%__MODULE__{} = message) do
    header =
      <<message.queue_slot::little-size(32), message.map::little-size(32), message.bracket::little-size(8),
        message.client_instance_id::little-size(32), Map.fetch!(@status, message.status)::little-size(32),
        message.time_one_ms::little-size(32)>>

    if message.status in [:wait_queue, :in_progress] do
      header <> <<message.time_two_ms::little-size(32)>>
    else
      header
    end
  end
end
