defmodule ThistleTea.Game.Core.Social do
  @moduledoc """
  A character's independent friend and ignore lists, with vanilla capacity
  limits and pure membership transitions.
  """

  defmodule Friend do
    @moduledoc false
    defstruct [:guid, status: 0, zone: 0, level: 0, class: 0]
  end

  defstruct [:owner_guid, friends: MapSet.new(), ignored: MapSet.new()]

  def limit(:friend), do: 50
  def limit(:ignore), do: 25

  def members(%__MODULE__{friends: friends}, :friend), do: friends
  def members(%__MODULE__{ignored: ignored}, :ignore), do: ignored

  def member?(%__MODULE__{} = social, kind, guid), do: MapSet.member?(members(social, kind), guid)

  def add(%__MODULE__{} = social, kind, guid) when kind in [:friend, :ignore] do
    members = members(social, kind)

    cond do
      not is_integer(guid) or guid <= 0 -> {:error, :not_found}
      social.owner_guid == guid -> {:error, :self}
      MapSet.member?(members, guid) -> {:error, :already}
      MapSet.size(members) >= limit(kind) -> {:error, :full}
      true -> {:ok, put_members(social, kind, MapSet.put(members, guid))}
    end
  end

  def remove(%__MODULE__{} = social, kind, guid) when kind in [:friend, :ignore] do
    put_members(social, kind, MapSet.delete(members(social, kind), guid))
  end

  def retain(%__MODULE__{} = social, keep?) when is_function(keep?, 1) do
    %{social | friends: MapSet.filter(social.friends, keep?), ignored: MapSet.filter(social.ignored, keep?)}
  end

  defp put_members(social, :friend, members), do: %{social | friends: members}
  defp put_members(social, :ignore, members), do: %{social | ignored: members}
end
