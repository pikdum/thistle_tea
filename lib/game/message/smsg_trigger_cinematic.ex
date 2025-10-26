defmodule ThistleTea.Game.Message.SmsgTriggerCinematic do
  use ThistleTea.Game.ServerMessage, :SMSG_TRIGGER_CINEMATIC

  defstruct [:cinematic_sequence_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{cinematic_sequence_id: cinematic_sequence_id}) do
    <<cinematic_sequence_id::little-size(32)>>
  end
end
