defmodule ThistleTea.Game.Message.SmsgWho do
  use ThistleTea.Game.ServerMessage, :SMSG_WHO

  defmodule WhoPlayer do
    defstruct [
      :name,
      :guild,
      :level,
      :class,
      :race,
      :area
    ]
  end

  defstruct [
    :listed_players,
    :online_players,
    :players
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        listed_players: listed_players,
        online_players: online_players,
        players: players
      }) do
    players_binary =
      players
      |> Enum.map(fn player ->
        player.name <>
          <<0>> <>
          player.guild <>
          <<0>> <>
          <<
            player.level::little-size(32),
            player.class::little-size(32),
            player.race::little-size(32),
            player.area::little-size(32)
          >>
      end)
      |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)

    <<listed_players::little-size(32), online_players::little-size(32)>> <> players_binary
  end
end
