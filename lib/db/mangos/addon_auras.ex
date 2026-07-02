defmodule ThistleTea.DB.Mangos.AddonAuras do
  @moduledoc """
  Parses space-separated spell-id lists stored in VMangos aura columns.
  """

  def parse(auras) when is_binary(auras) do
    auras
    |> String.split(" ", trim: true)
    |> Enum.flat_map(fn token ->
      case Integer.parse(token) do
        {spell_id, ""} when spell_id > 0 -> [spell_id]
        _ -> []
      end
    end)
  end

  def parse(_auras), do: []
end
