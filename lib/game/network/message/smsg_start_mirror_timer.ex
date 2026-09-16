defmodule ThistleTea.Game.Network.Message.SmsgStartMirrorTimer do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_START_MIRROR_TIMER

  defstruct [:timer, :remaining, :duration, :scale, frozen: 0, spell_id: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.timer::little-size(32), message.remaining::little-size(32), message.duration::little-size(32),
      message.scale::signed-little-size(32), message.frozen::little-size(8), message.spell_id::little-size(32)>>
  end
end
