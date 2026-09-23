defmodule ThistleTea.Game.Player.Weather do
  @moduledoc "Player-owned weather subscriptions, stale-update rejection, and developer controls."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.SmsgWeather
  alias ThistleTea.Game.Player.Rest
  alias ThistleTea.Game.Weather
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Weather, as: WeatherSystem

  def refresh(%State{ready: true, character: %Character{} = character} = state, zone) do
    key = {character.internal.world, zone || 0}

    if state.weather_key == key do
      state
    else
      {world, zone} = key
      {token, weather} = WeatherSystem.sync(state.guid, world, zone)
      project(weather)
      %{state | weather_key: key, weather_token: token}
    end
  end

  def refresh(state, _zone), do: state

  def update(
        %State{
          ready: true,
          pending_worldport?: false,
          weather_token: token,
          weather_key: {world, _zone},
          character: %Character{internal: %{world: world}}
        } = state,
        token,
        %Weather{} = weather
      )
      when is_reference(token) do
    project(weather)
    state
  end

  def update(state, _token, _weather), do: state

  def leave(%State{weather_key: nil} = state), do: state

  def leave(%State{} = state) do
    WeatherSystem.leave(state.guid)
    %{state | weather_key: nil, weather_token: nil}
  end

  def command(%State{ready: true, character: %Character{} = character} = state, args) do
    {x, y, z, _orientation} = character.movement_block.position

    zone =
      case Pathfinding.get_zone_and_area(character.internal.world.map_id, {x, y, z}) do
        {zone, _area} -> zone
        _missing -> Rest.default_zone(character.internal.world.map_id)
      end

    state = refresh(state, zone)

    if is_integer(zone) and zone > 0 do
      result = control(character.internal.world, zone, args)
      {state, describe(result, zone)}
    else
      {state, "Weather unavailable: the server could not resolve this zone."}
    end
  end

  def command(state, _args), do: {state, "Weather unavailable while entering the world."}

  defp control(world, zone, []), do: WeatherSystem.snapshot().zones[{world, zone}].weather
  defp control(world, zone, ["auto"]), do: WeatherSystem.resume(world, zone)
  defp control(world, zone, ["step"]), do: WeatherSystem.advance(world, zone)
  defp control(world, zone, ["fine"]), do: WeatherSystem.set(world, zone, :fine, 0.0)

  defp control(world, zone, [type, grade | options]) when options in [[], ["permanent"]] do
    type = %{"fine" => :fine, "rain" => :rain, "snow" => :snow, "storm" => :storm}[type]

    case Float.parse(grade) do
      {grade, ""} -> WeatherSystem.set(world, zone, type, grade, options == ["permanent"])
      _invalid -> {:error, :invalid_weather}
    end
  end

  defp control(_world, _zone, _args), do: {:error, :invalid_weather}

  defp describe(%Weather{} = weather, zone),
    do: "Zone #{zone} weather: #{weather.type}, intensity #{Float.round(weather.grade, 4)}."

  defp describe(_error, _zone), do: "Use: .weather [fine|auto|step] or .weather <rain|snow|storm> <0..1> [permanent]"

  defp project(%Weather{} = weather) do
    Network.send_packet(%SmsgWeather{
      weather_type: Weather.type_id(weather),
      grade: weather.grade,
      sound_id: Weather.sound(weather)
    })
  end
end
