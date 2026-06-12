defmodule ThistleTea.Game.Network.Message.CmsgWho do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_WHO

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgWho.WhoPlayer
  alias ThistleTea.Game.World.CharacterStore

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
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

    Network.send_packet(%Message.SmsgWho{
      listed_players: count,
      online_players: count,
      players: players
    })

    state
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
