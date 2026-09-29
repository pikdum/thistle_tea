defmodule ThistleTea.Game.World.Topics do
  @moduledoc """
  Group keys for world facts that an owner publishes and interested processes
  subscribe to.

  The owner of a fact dispatches a message when the fact changes; subscribers
  react instead of polling. Membership is per process and disappears with it.
  """

  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Groups

  @group Groups

  def subscribe(key) when is_binary(key), do: Group.join(@group, key, %{})

  def unsubscribe(key) when is_binary(key), do: Group.leave(@group, key)

  def publish(key, message) when is_binary(key), do: Group.dispatch(@group, key, message)

  def game_event(event) when is_integer(event), do: "game_event/#{event}"

  def creature_event(event) when is_integer(event), do: "creature_event/#{event}"

  def game_events, do: "game_events"

  def world_facts(%WorldRef{map_id: map_id, instance_id: instance_id}),
    do: "world_facts/#{map_id}/#{instance_id || "world"}"
end
