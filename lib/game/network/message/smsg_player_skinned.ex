defmodule ThistleTea.Game.Network.Message.SmsgPlayerSkinned do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PLAYER_SKINNED

  defstruct spirit_released: false

  @impl ServerMessage
  def to_binary(%__MODULE__{spirit_released: released?}), do: <<if(released?, do: 1, else: 0)::8>>
end
