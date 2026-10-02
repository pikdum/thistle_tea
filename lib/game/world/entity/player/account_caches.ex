defmodule ThistleTea.Game.World.Entity.Player.AccountCaches do
  @moduledoc """
  Keeps the client caches a player uploads and answers requests for them,
  filing each under its account or character, and publishes their MD5s at
  login so the client only transfers caches that differ.
  """

  alias ThistleTea.Game.Core.Player.AccountData
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.AccountDataStore
  alias ThistleTea.Game.World.Outbound

  def store(account_id, character_guid, type, data) when is_binary(data) do
    if AccountData.type?(type) and AccountData.fits?(data),
      do: type |> AccountData.owner(account_id, character_guid) |> AccountDataStore.put_cache(type, data)

    :ok
  end

  def store(_account_id, _character_guid, _type, _data), do: :ok

  def send(account_id, character_guid, type) do
    if AccountData.type?(type) do
      data = type |> AccountData.owner(account_id, character_guid) |> AccountDataStore.cache(type)
      Outbound.send_packet(%Message.SmsgUpdateAccountData{type: type, data: data})
    end

    :ok
  end

  def digests(account_id, character_guid) do
    digests =
      Enum.map(AccountData.types(), fn type ->
        type |> AccountData.owner(account_id, character_guid) |> AccountDataStore.cache(type) |> AccountData.digest()
      end)

    %Message.SmsgAccountDataMd5{digests: digests}
  end
end
