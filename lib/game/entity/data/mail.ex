defmodule ThistleTea.Game.Entity.Data.Mail do
  @moduledoc """
  Runtime mail data. Mailboxes contain these values while their character is
  online; the Post Office contains the same values while the character is
  offline.
  """

  defstruct [
    :id,
    :sender,
    :receiver,
    :deliver_at,
    :expire_at,
    sender_type: :normal,
    subject: "",
    body: "",
    stationery: 41,
    template_id: 0,
    item_guid: 0,
    money: 0,
    cod: 0,
    checked: 0
  ]
end
