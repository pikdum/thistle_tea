defmodule ThistleTea.Game.Network.Message.SmsgActionButtons do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ACTION_BUTTONS

  @max_action_buttons 120

  defstruct buttons: %{}

  def max_action_buttons, do: @max_action_buttons

  @impl ServerMessage
  def to_binary(%__MODULE__{buttons: buttons}) do
    for index <- 0..(@max_action_buttons - 1), into: <<>> do
      <<Map.get(buttons, index, 0)::little-size(32)>>
    end
  end
end
