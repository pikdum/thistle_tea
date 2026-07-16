defmodule ThistleTea.Game.Network.Message.SmsgUpdateInstanceOwnership do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_UPDATE_INSTANCE_OWNERSHIP

  defstruct player_is_saved_to_a_raid: false

  @impl ServerMessage
  def to_binary(%__MODULE__{player_is_saved_to_a_raid: saved?}) do
    <<bool32(saved?)::little-size(32)>>
  end

  defp bool32(true), do: 1
  defp bool32(false), do: 0
end
