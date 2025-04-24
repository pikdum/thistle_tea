defprotocol ThistleTeaGame.ClientPacket.Protocol do
  def handle(packet, conn)
  def opcode(packet)
end
