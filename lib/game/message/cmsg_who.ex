defmodule ThistleTea.Game.Message.CmsgWho do
  use ThistleTea.Game.ClientMessage, :CMSG_WHO

  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgWho.WhoPlayer
  alias ThistleTea.Util

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    characters =
      ThistleTea.Character.get_all()
      |> Enum.filter(fn c -> :ets.member(:entities, c.id) end)

    count = Enum.count(characters)

    players =
      characters
      |> Enum.map(fn c ->
        %WhoPlayer{
          name: c.name,
          guild: "Test Guild",
          level: c.level,
          class: c.class,
          race: c.race,
          area: c.area
        }
      end)

    Util.send_packet(%Message.SmsgWho{
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
