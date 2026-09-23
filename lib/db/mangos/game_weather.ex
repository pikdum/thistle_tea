defmodule ThistleTea.DB.Mangos.GameWeather do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:zone, :integer, autogenerate: false}

  schema "game_weather" do
    for season <- [:spring, :summer, :fall, :winter], type <- [:rain, :snow, :storm] do
      field(:"#{season}_#{type}_chance", :integer, default: 25)
    end
  end
end
