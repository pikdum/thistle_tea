defmodule ThistleTea.Game.Network.Message.SmsgDuelWinner do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DUEL_WINNER

  defstruct [:winner_name, :loser_name, fled?: false]

  @impl ServerMessage
  def to_binary(%__MODULE__{fled?: fled?, winner_name: winner_name, loser_name: loser_name}) do
    <<if(fled?, do: 1, else: 0)::little-size(8)>> <>
      winner_name <>
      <<0>> <>
      loser_name <> <<0>>
  end
end
