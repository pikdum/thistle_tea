defmodule ThistleTea.Game.Network.Message.SmsgTradeStatus do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TRADE_STATUS

  @statuses %{
    busy: 0,
    begin_trade: 1,
    open_window: 2,
    trade_canceled: 3,
    trade_accept: 4,
    no_target: 6,
    back_to_trade: 7,
    trade_complete: 8,
    trade_rejected: 9,
    target_to_far: 10,
    wrong_faction: 11,
    close_window: 12,
    ignore_you: 14,
    you_stunned: 15,
    target_stunned: 16,
    you_dead: 17,
    target_dead: 18,
    you_logout: 19,
    target_logout: 20
  }

  defstruct status: :trade_canceled, player_guid: 0, inventory_result: 0, target_error: false, category: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<Map.fetch!(@statuses, message.status)::little-size(32)>> <> details(message)
  end

  defp details(%__MODULE__{status: :begin_trade, player_guid: guid}), do: <<guid::little-size(64)>>

  defp details(%__MODULE__{status: :close_window} = message) do
    <<message.inventory_result::little-size(32), if(message.target_error, do: 1, else: 0),
      message.category::little-size(32)>>
  end

  defp details(_message), do: <<>>
end
