defmodule ThistleTea.Game.World.Inbound.Social do
  @moduledoc "Handles decoded friend, ignore, who, and inspect client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgWho.WhoPlayer
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Honor
  alias ThistleTea.Game.World.Entity.Player.Inspection
  alias ThistleTea.Game.World.Entity.Player.Social
  alias ThistleTea.Game.World.Outbound

  def messages do
    [
      Message.CmsgAddFriend,
      Message.CmsgAddIgnore,
      Message.CmsgChatIgnored,
      Message.CmsgDelFriend,
      Message.CmsgDelIgnore,
      Message.CmsgFriendList,
      Message.CmsgInspect,
      Message.CmsgInspectHonorStats,
      Message.CmsgWho
    ]
  end

  def handle(%Message.CmsgAddFriend{name: name}, state), do: Social.add(state, :friend, name)

  def handle(%Message.CmsgAddIgnore{name: name}, state), do: Social.add(state, :ignore, name)

  def handle(%Message.CmsgChatIgnored{guid: guid}, state), do: Social.ignored(state, guid)

  def handle(%Message.CmsgDelFriend{guid: guid}, state), do: Social.remove(state, :friend, guid)

  def handle(%Message.CmsgDelIgnore{guid: guid}, state), do: Social.remove(state, :ignore, guid)

  def handle(%Message.CmsgFriendList{}, state), do: Social.list(state)

  def handle(%Message.CmsgInspect{guid: guid}, state), do: Inspection.inspect(state, guid)

  def handle(%Message.CmsgInspectHonorStats{guid: guid}, state), do: Honor.inspect(state, guid)

  def handle(%Message.CmsgWho{}, state) do
    characters =
      CharacterStore.all()
      |> Enum.filter(fn c -> Entity.online?(c.id) end)

    count = Enum.count(characters)

    players =
      characters
      |> Enum.map(fn c ->
        %WhoPlayer{
          name: c.internal.name,
          guild: "Test Guild",
          level: c.unit.level,
          class: c.unit.class,
          race: c.unit.race,
          area: c.internal.area
        }
      end)

    Outbound.send_packet(%Message.SmsgWho{
      listed_players: count,
      online_players: count,
      players: players
    })

    state
  end
end
