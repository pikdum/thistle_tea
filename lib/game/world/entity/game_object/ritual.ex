defmodule ThistleTea.Game.World.Entity.GameObject.Ritual do
  @moduledoc """
  Pure unique-participant accounting for summoning ritual game objects.

  Helpers of a grouped ritual must share a group with its owner, or with its
  first participant when it has no owner. A persistent ritual can be
  completed again once enough participants leave, as vmangos sets it back to
  ready, and `reset/1` clears a placed one for its next use.
  """

  alias ThistleTea.Game.Core.Entity.Component.Internal.Ritual

  def use(%Ritual{completed?: true} = ritual, _user_guid, _same_group?), do: {ritual, :ignored}

  def use(%Ritual{owner_guid: user_guid} = ritual, user_guid, _same_group?), do: {ritual, :ignored}

  def use(%Ritual{} = ritual, user_guid, same_group?) when is_integer(user_guid) do
    cond do
      MapSet.member?(ritual.users, user_guid) -> {ritual, :ignored}
      ritual.casters_grouped? and not same_group? and anchored_elsewhere?(ritual, user_guid) -> {ritual, :ignored}
      true -> join(ritual, user_guid)
    end
  end

  def leave(%Ritual{} = ritual, user_guid) when is_integer(user_guid) do
    users = MapSet.delete(ritual.users, user_guid)

    completed? =
      ritual.completed? and not (ritual.persistent? and MapSet.size(users) < ritual.required_participants)

    %{ritual | users: users, first_user_guid: leader(ritual, users), completed?: completed?}
  end

  def reset(%Ritual{owner_guid: nil} = ritual),
    do: %{ritual | users: MapSet.new(), first_user_guid: nil, completed?: false}

  def anchor(%Ritual{owner_guid: owner_guid, first_user_guid: first_user_guid}), do: owner_guid || first_user_guid

  defp leader(%Ritual{owner_guid: nil, first_user_guid: first_user_guid}, users),
    do: if(MapSet.size(users) > 0, do: first_user_guid)

  defp leader(%Ritual{first_user_guid: first_user_guid}, _users), do: first_user_guid

  defp anchored_elsewhere?(ritual, user_guid) do
    case anchor(ritual) do
      anchor when is_integer(anchor) -> anchor != user_guid
      nil -> false
    end
  end

  defp join(ritual, user_guid) do
    users = MapSet.put(ritual.users, user_guid)
    ritual = %{ritual | users: users, first_user_guid: ritual.first_user_guid || user_guid}

    if MapSet.size(users) >= ritual.required_participants,
      do: {%{ritual | completed?: true}, :complete},
      else: {ritual, :waiting}
  end
end
