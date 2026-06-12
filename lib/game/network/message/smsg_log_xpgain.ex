defmodule ThistleTea.Game.Network.Message.SmsgLogXpgain do
  @moduledoc false

  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOG_XPGAIN

  defstruct target: 0,
            total_exp: 0,
            exp_type: :kill,
            experience_without_rested: 0,
            exp_group_bonus: 1.0

  @impl ServerMessage
  def to_binary(%__MODULE__{exp_type: :non_kill} = message) do
    <<message.target::little-size(64), message.total_exp::little-size(32), 1::little-size(8)>>
  end

  def to_binary(%__MODULE__{} = message) do
    <<message.target::little-size(64), message.total_exp::little-size(32), 0::little-size(8),
      message.experience_without_rested::little-size(32), message.exp_group_bonus::little-float-size(32)>>
  end
end
