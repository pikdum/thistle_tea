defmodule ThistleTea.Game.Core.GmTicket do
  @moduledoc """
  A player's help request, as the 1.12 help frame files it: one open ticket
  per character, with a category, the player's text, and where they stood.
  Answering a ticket completes it; the player then sees the answer appended
  below their text and can only replace it with a new ticket. Ages are
  reported to the client in days.
  """

  @types 1..10
  @day_ms 86_400_000

  @enforce_keys [:id, :player_guid, :type, :message, :created_at, :modified_at]
  defstruct [
    :id,
    :player_guid,
    :player_name,
    :type,
    :message,
    :map_id,
    :position,
    :created_at,
    :modified_at,
    :response,
    completed?: false,
    viewed?: false
  ]

  def type?(type), do: type in @types

  def new(id, player_guid, player_name, type, message, map_id, position, now) when type in @types do
    %__MODULE__{
      id: id,
      player_guid: player_guid,
      player_name: player_name,
      type: type,
      message: message,
      map_id: map_id,
      position: position,
      created_at: now,
      modified_at: now
    }
  end

  def update_text(%__MODULE__{completed?: false} = ticket, type, message, now) when type in @types,
    do: {:ok, %{ticket | type: type, message: message, modified_at: now}}

  def update_text(%__MODULE__{}, _type, _message, _now), do: :error

  def respond(%__MODULE__{} = ticket, response, now) when is_binary(response),
    do: %{ticket | response: response, completed?: true, viewed?: true, modified_at: now}

  def display_message(%__MODULE__{completed?: false, message: message}), do: message

  def display_message(%__MODULE__{} = ticket) do
    answer = if ticket.response in [nil, ""], do: "", else: "\n    GM answer:\n" <> ticket.response

    ticket.message <>
      "\n\n-----------------------------------------------------------------------\n" <>
      "Customer ticket ##{ticket.id} completed.\n" <> answer
  end

  def age_days(at, now) when is_integer(at) and is_integer(now), do: max(now - at, 0) / @day_ms
  def age_days(_at, _now), do: 0.0
end
