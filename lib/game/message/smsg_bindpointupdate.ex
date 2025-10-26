defmodule ThistleTea.Game.Message.SmsgBindpointupdate do
  use ThistleTea.Game.ServerMessage, :SMSG_BINDPOINTUPDATE

  defstruct [
    :x,
    :y,
    :z,
    :map,
    :area
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        x: x,
        y: y,
        z: z,
        map: map,
        area: area
      }) do
    <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
      map::little-size(32), area::little-size(32)>>
  end
end
