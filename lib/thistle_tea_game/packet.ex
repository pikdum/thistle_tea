defprotocol ThistleTeaGame.Packet do
  def handle(packet, conn)
end
