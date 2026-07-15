defmodule ThistleTea.Game.Network.Message.SmsgMailListResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MAIL_LIST_RESULT

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Mail
  alias ThistleTea.Game.Entity.Logic.Mail, as: MailLogic

  defstruct mails: [], now: 0

  @day_ms to_timeout(day: 1)

  @impl ServerMessage
  def to_binary(%__MODULE__{mails: mails, now: now}) do
    mails = Enum.take(mails, 254)
    <<length(mails)>> <> Enum.map_join(mails, &mail_binary(&1, now))
  end

  defp mail_binary({%Mail{} = mail, item}, now) do
    <<mail.id::little-size(32)>> <>
      <<mail_type(mail.sender_type)>> <>
      sender_binary(mail) <>
      mail.subject <>
      <<0, MailLogic.item_text_id(mail)::little-size(32), 0::little-size(32), mail.stationery::little-size(32)>> <>
      item_binary(item) <>
      <<mail.money::little-size(32), mail.cod::little-size(32), mail.checked::little-size(32),
        expiration_days(mail, now)::little-float-size(32), mail.template_id::little-size(32)>>
  end

  defp sender_binary(%Mail{sender_type: :normal, sender: sender}), do: <<sender::little-size(64)>>

  defp sender_binary(%Mail{sender_type: type, sender: sender}) when type in [:auction, :creature, :game_object],
    do: <<sender::little-size(32)>>

  defp sender_binary(%Mail{}), do: <<>>

  defp item_binary(%Item{} = item) do
    permanent_enchantment = (item.item.enchantment || 0) &&& 0xFFFFFFFF
    charges = (item.item.spell_charges || 0) &&& 0xFFFFFFFF

    <<item.object.entry::little-size(32), permanent_enchantment::little-size(32),
      item.item.random_properties_id || 0::little-size(32), item.item.property_seed || 0::little-size(32),
      item.item.stack_count || 1, charges::little-size(32), item.item.max_durability || 0::little-size(32),
      item.item.durability || 0::little-size(32)>>
  end

  defp item_binary(_item), do: <<0::little-size(32 * 4), 0, 0::little-size(32 * 3)>>

  defp expiration_days(%Mail{expire_at: expire_at}, now), do: max(expire_at - now, 0) / @day_ms

  defp mail_type(:normal), do: 0
  defp mail_type(:auction), do: 2
  defp mail_type(:creature), do: 3
  defp mail_type(:game_object), do: 4
  defp mail_type(:item), do: 5
end
