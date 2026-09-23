defmodule ThistleTea.Game.Network.Message.SmsgGuildQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GUILD_QUERY_RESPONSE

  alias ThistleTea.Game.Guild.Group

  defstruct [:guild]

  @impl ServerMessage
  def to_binary(%__MODULE__{guild: %Group{} = guild}) do
    ranks = Enum.map(guild.ranks, &(&1.name <> <<0>>))
    rank_names = IO.iodata_to_binary(ranks ++ List.duplicate(<<0>>, 10 - length(ranks)))
    {style, color, border, border_color, background} = guild.emblem

    <<guild.id::little-size(32)>> <>
      guild.name <>
      <<0>> <>
      rank_names <>
      <<style::little-size(32), color::little-size(32), border::little-size(32), border_color::little-size(32),
        background::little-size(32)>>
  end
end
