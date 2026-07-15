defmodule ThistleTea.Game.Network.Message.CmsgSendMail do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SEND_MAIL

  alias ThistleTea.Game.Player.Mail

  defstruct [:mailbox, :receiver, :subject, :body, :stationery, :item_guid, money: 0, cod: 0]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Mail.send_mail(state, message)

  @impl ClientMessage
  def from_binary(<<mailbox::little-size(64), rest::binary>>) do
    {:ok, receiver, rest} = BinaryUtils.parse_string(rest)
    {:ok, subject, rest} = BinaryUtils.parse_string(rest)
    {:ok, body, rest} = BinaryUtils.parse_string(rest)

    <<stationery::little-size(32), _package::little-size(32), item_guid::little-size(64), money::little-size(32),
      cod::little-size(32), _rest::binary>> = rest

    %__MODULE__{
      mailbox: mailbox,
      receiver: String.capitalize(String.downcase(receiver)),
      subject: subject,
      body: body,
      stationery: stationery,
      item_guid: item_guid,
      money: money,
      cod: cod
    }
  end
end
