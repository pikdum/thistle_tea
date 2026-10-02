defmodule ThistleTea.Game.Core.Player.AccountData do
  @moduledoc """
  The eight client caches the server keeps for a player: config, key
  bindings, and macros shared by the whole account, plus each character's
  own config, bindings, macros, layout, and chat settings. The server only
  stores the text; at login it sends each cache's MD5 so the client uploads
  what changed and downloads what it lacks. An empty cache hashes to zeros.
  """

  @types 0..7
  @account_types [0, 2, 4]
  @max_size 0xFFFF

  def types, do: Enum.to_list(@types)

  def type?(type), do: type in @types

  def scope(type) when type in @account_types, do: :account
  def scope(type) when type in @types, do: :character

  def owner(type, account_id, character_guid) do
    case scope(type) do
      :account when is_integer(account_id) -> {:account, account_id}
      :character when is_integer(character_guid) -> {:character, character_guid}
      _scope -> nil
    end
  end

  def fits?(data) when is_binary(data), do: byte_size(data) <= @max_size

  def digest(""), do: <<0::128>>
  def digest(data) when is_binary(data), do: :crypto.hash(:md5, data)
end
