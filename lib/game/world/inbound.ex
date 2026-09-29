defmodule ThistleTea.Game.World.Inbound do
  @moduledoc """
  Dispatch table from decoded client messages to their world handlers.

  Network message modules only encode and decode. The connection hands
  pre-login messages here with its `ConnectionState`; once a player entity
  exists, its process routes every message here with the player state.
  """
  alias ThistleTea.Game.World.Inbound.Auction
  alias ThistleTea.Game.World.Inbound.Character
  alias ThistleTea.Game.World.Inbound.Chat
  alias ThistleTea.Game.World.Inbound.Combat
  alias ThistleTea.Game.World.Inbound.Death
  alias ThistleTea.Game.World.Inbound.Group
  alias ThistleTea.Game.World.Inbound.Guild
  alias ThistleTea.Game.World.Inbound.Instance
  alias ThistleTea.Game.World.Inbound.Interaction
  alias ThistleTea.Game.World.Inbound.Item
  alias ThistleTea.Game.World.Inbound.Login
  alias ThistleTea.Game.World.Inbound.Loot
  alias ThistleTea.Game.World.Inbound.Mail
  alias ThistleTea.Game.World.Inbound.Movement
  alias ThistleTea.Game.World.Inbound.Pet
  alias ThistleTea.Game.World.Inbound.Pvp
  alias ThistleTea.Game.World.Inbound.Query
  alias ThistleTea.Game.World.Inbound.Quest
  alias ThistleTea.Game.World.Inbound.Social
  alias ThistleTea.Game.World.Inbound.Spell
  alias ThistleTea.Game.World.Inbound.Trade
  alias ThistleTea.Game.World.Inbound.Travel
  alias ThistleTea.Game.World.Inbound.Vendor

  @handlers [
    Auction,
    Character,
    Chat,
    Combat,
    Death,
    Group,
    Guild,
    Instance,
    Interaction,
    Item,
    Login,
    Loot,
    Mail,
    Movement,
    Pet,
    Pvp,
    Query,
    Quest,
    Social,
    Spell,
    Trade,
    Travel,
    Vendor
  ]
  @routes for handler <- @handlers, message <- handler.messages(), into: %{}, do: {message, handler}

  def handle(%message{} = struct, state), do: Map.fetch!(@routes, message).handle(struct, state)

  def messages, do: Map.keys(@routes)

  def routed?(message) when is_atom(message), do: Map.has_key?(@routes, message)
end
