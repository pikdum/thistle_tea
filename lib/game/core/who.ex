defmodule ThistleTea.Game.Core.Who do
  @moduledoc """
  The `/who` list, after vmangos `WhoListClientQueryTask`: the online players
  of the asker's team who pass every filter of the query, at most 49 of them.

  A player is listed when their level is in range, their race and class are
  in the query's masks, their name and guild contain the name and guild
  filters, their zone is one of the query's zones (when it names any), and
  any of its search terms appears in their name, guild, or zone name. Inside
  a battleground, players in the asker's zone are listed only from the
  asker's own copy of it. Every filter ignores case. The online count is the
  number listed, unless more than 49 players are online.
  """

  import Bitwise, only: [&&&: 2, <<<: 2]

  defmodule Query do
    @moduledoc false
    defstruct level_min: 0,
              level_max: 100,
              name: "",
              guild: "",
              race_mask: 0xFFFF_FFFF,
              class_mask: 0xFFFF_FFFF,
              zones: [],
              terms: []
  end

  defmodule Entry do
    @moduledoc false
    defstruct [:guid, :name, :level, :class, :race, :team, :zone, :world, guild: "", zone_name: ""]
  end

  @max_listed 49
  @battleground_zones [2597, 3277, 3358]

  def list(%Query{} = query, %Entry{} = asker, entries) when is_list(entries) do
    query = normalize(query)
    listed = entries |> Enum.filter(&listed?(query, asker, &1)) |> Enum.take(@max_listed)
    online = length(entries)
    {listed, if(online > @max_listed, do: online, else: length(listed))}
  end

  defp normalize(%Query{} = query) do
    %{
      query
      | name: String.downcase(query.name),
        guild: String.downcase(query.guild),
        terms: Enum.map(query.terms, &String.downcase/1)
    }
  end

  defp listed?(%Query{} = query, %Entry{} = asker, %Entry{} = entry) do
    entry.team == asker.team and
      entry.level in query.level_min..query.level_max//1 and
      in_mask?(query.class_mask, entry.class) and
      in_mask?(query.race_mask, entry.race) and
      contains?(entry.name, query.name) and
      contains?(entry.guild, query.guild) and
      zone_shown?(query.zones, asker, entry) and
      term_shown?(query.terms, entry)
  end

  defp in_mask?(mask, id) when is_integer(id), do: (mask &&& 1 <<< id) != 0
  defp in_mask?(_mask, _id), do: false

  defp contains?(_text, ""), do: true
  defp contains?(text, filter), do: text |> String.downcase() |> String.contains?(filter)

  defp zone_shown?([], _asker, _entry), do: true

  defp zone_shown?(zones, %Entry{} = asker, %Entry{zone: zone} = entry) do
    zone in zones and (zone != asker.zone or asker.zone not in @battleground_zones or entry.world == asker.world)
  end

  defp term_shown?(terms, %Entry{} = entry) do
    Enum.reduce_while(terms, true, fn
      "", shown? ->
        {:cont, shown?}

      term, _shown? ->
        if Enum.any?([entry.name, entry.guild, entry.zone_name], &contains?(&1, term)),
          do: {:halt, true},
          else: {:cont, false}
    end)
  end
end
