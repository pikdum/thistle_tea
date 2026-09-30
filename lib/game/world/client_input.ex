defprotocol ThistleTea.Game.World.ClientInput do
  @moduledoc """
  A decoded client message applied to the state that received it: the player
  entity's state once the character is in the world, or the connection's
  state before that.

  The world owns this protocol and `ThistleTea.Game.Inbound` implements it,
  one message module at a time, so a player process can apply client input
  without knowing any wire format. `while_possessed?/1` is true for the
  messages a player's client still sends while another unit possesses the
  player: connection, chat, logout, cache query, and movement acknowledgement
  traffic.
  """

  def handle(message, state)
  def while_possessed?(message)
end
