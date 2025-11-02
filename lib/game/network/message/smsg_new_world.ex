defmodule ThistleTea.Game.Network.Message.SmsgNewWorld do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_NEW_WORLD

  defstruct [
    :map,
    :position,
    :orientation
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map, position: %{x: x, y: y, z: z}, orientation: orientation}) do
    <<
      map::little-size(32),
      x::little-float-size(32),
      y::little-float-size(32),
      z::little-float-size(32),
      orientation::little-float-size(32)
    >>
  end
end
