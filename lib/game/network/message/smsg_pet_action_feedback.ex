defmodule ThistleTea.Game.Network.Message.SmsgPetActionFeedback do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_ACTION_FEEDBACK

  @feedback_codes %{
    pet_dead: 1,
    nothing_to_attack: 2,
    cant_attack_target: 3,
    no_path_to: 4
  }

  defstruct [:feedback]

  def new(feedback) when is_map_key(@feedback_codes, feedback), do: %__MODULE__{feedback: feedback}

  @impl ServerMessage
  def to_binary(%__MODULE__{feedback: feedback}) do
    <<Map.fetch!(@feedback_codes, feedback)::little-size(8)>>
  end
end
