defimpl ThistleTea.Game.World.ClientInput, for: ThistleTea.Game.Network.Message.MsgMove do
  use Boundary, classify_to: ThistleTea.Game.Inbound

  alias ThistleTea.Game.World.Entity.Player.Movement

  def handle(message, state), do: Movement.handle(message, state)
  def while_possessed?(_message), do: false
end
