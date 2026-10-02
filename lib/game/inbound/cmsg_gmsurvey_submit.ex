defmodule ThistleTea.Game.Inbound.CmsgGmsurveySubmit do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_GMSURVEY_SUBMIT, while_possessed: true

  require Logger

  @max_questions 10

  defstruct [:survey_id, answers: [], comment: ""]

  @impl ClientMessage
  def from_binary(<<survey_id::little-size(32), rest::binary>>) do
    {answers, rest} = answers(rest, [], @max_questions)
    {:ok, comment, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{survey_id: survey_id, answers: answers, comment: comment}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = survey, %{character: %{internal: %{name: name}}} = state) do
    Logger.info("GM survey #{survey.survey_id} from #{name}: #{inspect(survey.answers)} #{survey.comment}")
    state
  end

  def handle(%__MODULE__{}, state), do: state

  defp answers(<<0::little-size(32), rest::binary>>, answers, _left), do: {Enum.reverse(answers), rest}
  defp answers(rest, answers, 0), do: {Enum.reverse(answers), rest}

  defp answers(<<question::little-size(32), rank::8, rest::binary>>, answers, left) do
    {:ok, comment, rest} = BinaryUtils.parse_string(rest)
    answers(rest, [{question, rank, comment} | answers], left - 1)
  end

  defp answers(rest, answers, _left), do: {Enum.reverse(answers), rest}
end
