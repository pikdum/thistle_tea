defmodule ThistleTea.Game.Network.Message.SmsgWeather do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_WEATHER

  defstruct weather_type: 0, grade: 0.0, sound_id: 0, instant?: false

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.weather_type::little-size(32), message.grade::little-float-size(32), message.sound_id::little-size(32),
      if(message.instant?, do: 1, else: 0)::8>>
  end
end
