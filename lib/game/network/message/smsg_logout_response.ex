defmodule ThistleTea.Game.Network.Message.SmsgLogoutResponse do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOGOUT_RESPONSE

  @result %{
    success: 0,
    failure_in_combat: 1,
    failure_frozen_by_gm: 2,
    failure_jumping_or_falling: 3
  }

  def result, do: @result
  def result(key), do: Map.fetch!(@result, key)

  @speed %{
    delayed: 0,
    instant: 1
  }

  def speed, do: @speed
  def speed(key), do: Map.fetch!(@speed, key)

  defstruct [
    :result,
    :speed
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result, speed: speed}) do
    <<result::little-size(32), speed::little-size(8)>>
  end
end
