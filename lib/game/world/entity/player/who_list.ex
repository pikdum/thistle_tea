defmodule ThistleTea.Game.World.Entity.Player.WhoList do
  @moduledoc """
  Answers a player's `/who` query from the live presence of every online
  player: their name, race, class, level, and area from `World.Metadata`,
  their copy of the world, and their guild's name, resolved in one guild
  system call. `Core.Who` filters the list.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Honor
  alias ThistleTea.Game.Core.Who
  alias ThistleTea.Game.Core.Who.Entry
  alias ThistleTea.Game.Core.Who.Query
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgWho.WhoPlayer
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem

  @presence [:name, :race, :class, :level, :area]

  def send(%{ready: true, guid: guid, character: %Character{}} = state, %Query{} = query) do
    entries = online_entries()

    case Enum.find(entries, &(&1.guid == guid)) do
      %Entry{} = asker ->
        {listed, online} = Who.list(query, asker, entries)

        Outbound.send_packet(%Message.SmsgWho{
          listed_players: length(listed),
          online_players: online,
          players: Enum.map(listed, &who_player/1)
        })

      nil ->
        :ok
    end

    state
  end

  def send(state, %Query{}), do: state

  def online_entries do
    guids = CharacterStore.all() |> Enum.map(& &1.id) |> Enum.filter(&Entity.online?/1)
    guilds = GuildSystem.names_of(guids)

    guids
    |> Enum.flat_map(&entry(&1, Map.get(guilds, &1, "")))
    |> Enum.sort_by(& &1.name)
  end

  defp entry(guid, guild) do
    with %{name: name, race: race, class: class, level: level} = presence <- Metadata.query(guid, @presence),
         {world, _x, _y, _z} <- World.position(guid) do
      zone = zone(Map.get(presence, :area))

      [
        %Entry{
          guid: guid,
          name: name,
          guild: guild,
          level: level,
          class: class,
          race: race,
          team: Honor.team(race),
          zone: zone,
          zone_name: zone_name(zone),
          world: world
        }
      ]
    else
      _offline -> []
    end
  end

  defp zone(area) when is_integer(area) and area > 0, do: World.zone_of(area)
  defp zone(_area), do: 0

  defp zone_name(zone) do
    case Exploration.area(zone) do
      %{name: name} when is_binary(name) -> name
      _unknown -> ""
    end
  end

  defp who_player(%Entry{} = entry) do
    %WhoPlayer{
      name: entry.name,
      guild: entry.guild,
      level: entry.level,
      class: entry.class,
      race: entry.race,
      area: entry.zone
    }
  end
end
