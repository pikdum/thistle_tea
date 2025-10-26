defprotocol ThistleTea.Game.Message do
  def to_binary(message)
  def to_packet(message)
end

defprotocol ThistleTea.Game.Handler do
  def handle(message, state)
end
