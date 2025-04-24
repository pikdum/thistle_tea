defprotocol ThistleTeaGame.ServerPacket.Protocol do
  def encode(packet)
  def opcode(packet)
end
