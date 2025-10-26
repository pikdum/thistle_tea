defmodule ThistleTea.Game.Message.SmsgTutorialFlags do
  use ThistleTea.Game.ServerMessage, :SMSG_TUTORIAL_FLAGS

  defstruct [:tutorial_data]

  @impl ServerMessage
  def to_binary(%__MODULE__{tutorial_data: tutorial_data}) do
    Enum.reduce(tutorial_data, <<>>, fn value, acc ->
      acc <> <<value::little-size(32)>>
    end)
  end
end
