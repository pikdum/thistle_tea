defmodule ThistleTea.Game.Network.Message.SmsgGuildCommandResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GUILD_COMMAND_RESULT

  defstruct [:command, name: "", result: :ok]

  @commands %{create: 0, invite: 1, quit: 3, founder: 14, roster: 19}
  @results %{
    ok: 0,
    internal: 1,
    already_in_guild: 2,
    already_invited: 5,
    invalid_name: 6,
    name_exists: 7,
    permissions: 8,
    leader_cannot_leave: 8,
    not_in_guild: 9,
    target_not_in_guild: 10,
    player_not_found: 11,
    wrong_faction: 12,
    rank_too_high: 13,
    rank_too_low: 14,
    not_invited: 1
  }

  @impl ServerMessage
  def to_binary(%__MODULE__{command: command, name: name, result: result}) do
    <<Map.fetch!(@commands, command)::little-size(32)>> <>
      name <>
      <<0>> <>
      <<Map.fetch!(@results, result)::little-size(32)>>
  end
end
