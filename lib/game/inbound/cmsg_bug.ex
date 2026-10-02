defmodule ThistleTea.Game.Inbound.CmsgBug do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_BUG, while_possessed: true

  require Logger

  defstruct [:suggestion?, :content, :type]

  @impl ClientMessage
  def from_binary(<<suggestion::little-size(32), _content_length::little-size(32), rest::binary>>) do
    {:ok, content, <<_type_length::little-size(32), rest::binary>>} = BinaryUtils.parse_string(rest)
    {:ok, type, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{suggestion?: suggestion != 0, content: content, type: type}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = report, state) do
    kind = if report.suggestion?, do: "suggestion", else: "bug"
    Logger.info("Player #{reporter(state)} reported a #{kind}: [#{report.type}] #{report.content}")
    state
  end

  defp reporter(%{character: %{internal: %{name: name}}}), do: name
  defp reporter(%{account: %{id: id}}), do: "account #{id}"
  defp reporter(_state), do: "(unknown)"
end
