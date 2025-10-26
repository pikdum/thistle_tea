defmodule ThistleTea.Game.Message.SmsgLoginVerifyWorld do
  use ThistleTea.Game.ServerMessage, :SMSG_LOGIN_VERIFY_WORLD

  defstruct [
    :map,
    :position,
    :orientation
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map, position: {x, y, z}, orientation: orientation}) do
    <<map::little-size(32), x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
      orientation::little-float-size(32)>>
  end
end
