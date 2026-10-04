defmodule ThistleTea.Game.World.Loader.GameTele do
  @moduledoc """
  Boot-loaded vmangos `game_tele` locations for the `.tele` dev command,
  matched by name: exactly first, then by prefix, then anywhere in the name,
  ignoring case.
  """

  alias ThistleTea.DB.Mangos

  @key {__MODULE__, :locations}

  def load_all do
    locations =
      Mangos.GameTele
      |> Mangos.Repo.all()
      |> Enum.map(
        &%{name: &1.name, map: &1.map, position: {&1.position_x, &1.position_y, &1.position_z, &1.orientation}}
      )
      |> Enum.sort_by(& &1.name)

    :persistent_term.put(@key, locations)
    :ok
  end

  def search(query), do: search(:persistent_term.get(@key, []), query)

  def search(locations, query) do
    wanted = query |> String.trim() |> String.downcase()
    named = Enum.map(locations, &{String.downcase(&1.name), &1})

    Enum.find_value(
      [:exact, :prefix, :anywhere],
      [],
      &nonempty(for {name, location} <- named, matches?(&1, name, wanted), do: location)
    )
  end

  defp nonempty([]), do: nil
  defp nonempty(found), do: found

  defp matches?(:exact, name, wanted), do: name == wanted
  defp matches?(:prefix, name, wanted), do: String.starts_with?(name, wanted)
  defp matches?(:anywhere, name, wanted), do: String.contains?(name, wanted)
end
