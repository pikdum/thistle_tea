defprotocol ThistleTeaGame.Effect do
  def process(effect, conn, socket)
end
