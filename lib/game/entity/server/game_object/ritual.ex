defmodule ThistleTea.Game.Entity.Server.GameObject.Ritual do
  @moduledoc """
  Pure unique-participant accounting for summoning ritual game objects.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual

  def use(%Ritual{completed?: true} = ritual, _user_guid, _same_group?), do: {ritual, :ignored}

  def use(%Ritual{owner_guid: user_guid} = ritual, user_guid, _same_group?), do: {ritual, :ignored}

  def use(%Ritual{casters_grouped?: true} = ritual, _user_guid, false), do: {ritual, :ignored}

  def use(%Ritual{} = ritual, user_guid, _same_group?) when is_integer(user_guid) do
    if MapSet.member?(ritual.users, user_guid) do
      {ritual, :ignored}
    else
      users = MapSet.put(ritual.users, user_guid)

      if MapSet.size(users) >= ritual.required_participants do
        {%{ritual | users: users, completed?: true}, :complete}
      else
        {%{ritual | users: users}, :waiting}
      end
    end
  end

  def leave(%Ritual{} = ritual, user_guid) when is_integer(user_guid) do
    %{ritual | users: MapSet.delete(ritual.users, user_guid)}
  end
end
