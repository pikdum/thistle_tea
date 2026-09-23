defmodule ThistleTea.Game.Guild.Petitions do
  @moduledoc """
  Pure guild charter and signature transitions. The runtime owner serializes
  these transitions while the player boundary owns inventory and packets.
  """

  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Guild.Member
  alias ThistleTea.Game.Party

  defmodule Signature do
    @moduledoc false
    @enforce_keys [:member, :account_id]
    defstruct @enforce_keys
  end

  defmodule Petition do
    @moduledoc false
    @enforce_keys [:id, :item_guid, :owner, :owner_account_id, :name]
    defstruct [:id, :item_guid, :owner, :owner_account_id, :name, signatures: %{}]
  end

  defstruct by_item: %{}, by_id: %{}, by_owner: %{}

  @required_signatures 9

  def required_signatures, do: @required_signatures

  def by_item(%__MODULE__{} = state, item_guid), do: Map.get(state.by_item, item_guid)

  def by_id(%__MODULE__{} = state, id) do
    case Map.fetch(state.by_id, id) do
      {:ok, item_guid} -> by_item(state, item_guid)
      :error -> nil
    end
  end

  def by_owner(%__MODULE__{} = state, guid) do
    case Map.fetch(state.by_owner, guid) do
      {:ok, item_guid} -> by_item(state, item_guid)
      :error -> nil
    end
  end

  def create(%__MODULE__{} = state, %Member{} = owner, account_id, item_guid, id, name)
      when is_integer(account_id) and is_integer(item_guid) and is_integer(id) and is_binary(name) do
    name = String.trim(name)

    cond do
      not Guild.valid_name?(name) ->
        {:error, :invalid_name}

      by_owner(state, owner.guid) != nil ->
        {:error, :already_invited}

      by_item(state, item_guid) != nil or by_id(state, id) != nil ->
        {:error, :internal}

      true ->
        put_new(state, %Petition{id: id, item_guid: item_guid, owner: owner, owner_account_id: account_id, name: name})
    end
  end

  defp put_new(state, petition) do
    updated = %{
      state
      | by_item: Map.put(state.by_item, petition.item_guid, petition),
        by_id: Map.put(state.by_id, petition.id, petition.item_guid),
        by_owner: Map.put(state.by_owner, petition.owner.guid, petition.item_guid)
    }

    {:ok, petition, updated}
  end

  def sign(%__MODULE__{} = state, item_guid, %Member{} = signer, account_id) when is_integer(account_id) do
    case by_item(state, item_guid) do
      %Petition{} = petition -> sign_petition(state, petition, signer, account_id)
      nil -> {:error, :not_found}
    end
  end

  defp sign_petition(state, petition, signer, account_id) do
    cond do
      signer.guid == petition.owner.guid ->
        {:error, :cant_sign_own}

      not Party.same_team?(petition.owner.race, signer.race) ->
        {:error, :wrong_faction}

      signed_account?(petition, account_id) ->
        {:error, :already_signed}

      map_size(petition.signatures) >= @required_signatures ->
        {:error, :complete}

      true ->
        signature = %Signature{member: signer, account_id: account_id}
        petition = %{petition | signatures: Map.put(petition.signatures, signer.guid, signature)}
        {:ok, petition, put_petition(state, petition)}
    end
  end

  defp signed_account?(petition, account_id) do
    account_id == petition.owner_account_id or
      Enum.any?(petition.signatures, fn {_guid, signature} -> signature.account_id == account_id end)
  end

  def rename(%__MODULE__{} = state, item_guid, owner_guid, name) when is_binary(name) do
    case by_item(state, item_guid) do
      %Petition{owner: %Member{guid: ^owner_guid}} = petition ->
        if Guild.valid_name?(name) do
          petition = %{petition | name: String.trim(name)}
          {:ok, petition, put_petition(state, petition)}
        else
          {:error, :invalid_name}
        end

      _ ->
        {:error, :not_found}
    end
  end

  def delete(%__MODULE__{} = state, item_guid) do
    case by_item(state, item_guid) do
      %Petition{} = petition ->
        updated = %{
          state
          | by_item: Map.delete(state.by_item, item_guid),
            by_id: Map.delete(state.by_id, petition.id),
            by_owner: Map.delete(state.by_owner, petition.owner.guid)
        }

        {:ok, petition, updated}

      nil ->
        {:error, :not_found}
    end
  end

  def revoke_signer(%__MODULE__{} = state, guid) do
    petitions =
      Map.new(state.by_item, fn {item_guid, petition} ->
        {item_guid, %{petition | signatures: Map.delete(petition.signatures, guid)}}
      end)

    %{state | by_item: petitions}
  end

  def complete?(%Petition{} = petition), do: map_size(petition.signatures) >= @required_signatures

  def signers(%Petition{} = petition) do
    petition.signatures
    |> Map.values()
    |> Enum.map(& &1.member)
  end

  defp put_petition(state, petition), do: %{state | by_item: Map.put(state.by_item, petition.item_guid, petition)}
end
