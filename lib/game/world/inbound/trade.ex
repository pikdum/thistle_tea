defmodule ThistleTea.Game.World.Inbound.Trade do
  @moduledoc "Handles decoded player trade client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Trade

  def messages do
    [
      Message.CmsgAcceptTrade,
      Message.CmsgBeginTrade,
      Message.CmsgBusyTrade,
      Message.CmsgCancelTrade,
      Message.CmsgClearTradeItem,
      Message.CmsgIgnoreTrade,
      Message.CmsgInitiateTrade,
      Message.CmsgSetTradeGold,
      Message.CmsgSetTradeItem,
      Message.CmsgUnacceptTrade
    ]
  end

  def handle(%Message.CmsgAcceptTrade{}, state), do: Trade.request(state, :accept)

  def handle(%Message.CmsgBeginTrade{}, state), do: Trade.request(state, :open)

  def handle(%Message.CmsgBusyTrade{}, state), do: Trade.request(state, {:cancel, :busy})

  def handle(%Message.CmsgCancelTrade{}, state), do: Trade.request(state, {:cancel, :trade_canceled})

  def handle(%Message.CmsgClearTradeItem{} = message, state), do: Trade.request(state, {:clear, message.trade_slot})

  def handle(%Message.CmsgIgnoreTrade{}, state), do: Trade.request(state, {:cancel, :ignore_you})

  def handle(%Message.CmsgInitiateTrade{} = message, state), do: Trade.request(state, {:initiate, message.player_guid})

  def handle(%Message.CmsgSetTradeGold{} = message, state), do: Trade.request(state, {:money, message.gold})

  def handle(%Message.CmsgSetTradeItem{} = message, state),
    do: Trade.request(state, {:item, message.trade_slot, message.bag, message.slot})

  def handle(%Message.CmsgUnacceptTrade{}, state), do: Trade.request(state, :unaccept)
end
