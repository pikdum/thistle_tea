defprotocol ThistleTeaGame.Packet do
  def handle(packet, conn)
  def encode(packet)
  def opcode(packet)
end
