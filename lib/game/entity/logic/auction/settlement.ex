defmodule ThistleTea.Game.Entity.Logic.Auction.Settlement do
  @moduledoc """
  Builds vanilla auction mail subjects, bodies, refunds, and attachments.
  Delivery keys distinguish successive refunds for the same bidder.
  """

  alias ThistleTea.Game.Entity.Data.Auction
  alias ThistleTea.Game.Entity.Data.Auction.Delivery

  @mail_types %{outbid: 0, won: 1, successful: 2, expired: 3, canceled_to_bidder: 4, canceled: 5}

  def refund(%Auction{} = auction, reason, now) when reason in [:outbid, :canceled_to_bidder] do
    auction |> delivery(reason, auction.bidder, now) |> with_money(auction.bid)
  end

  def returned(%Auction{} = auction, reason, now) when reason in [:expired, :canceled] do
    auction |> delivery(reason, auction.owner, now) |> with_item(auction.item)
  end

  def sold(%Auction{} = auction, cut, now) do
    won =
      auction
      |> delivery(:won, auction.bidder, now)
      |> with_body("#{guid_text(auction.owner)}:#{auction.bid}:#{auction.buyout}")
      |> with_item(auction.item)

    successful =
      auction
      |> delivery(:successful, auction.owner, now)
      |> with_body("#{guid_text(auction.bidder)}:#{auction.bid}:#{auction.buyout}:#{auction.deposit}:#{cut}")
      |> with_money(auction.bid + auction.deposit - cut)

    [won, successful]
  end

  defp delivery(auction, reason, receiver, now) do
    %Delivery{
      key: {:auction, auction.id, auction.revision, reason},
      attrs: %{
        sender_type: :auction,
        sender: auction.house.id,
        receiver: receiver,
        subject: "#{auction.item.object.entry}:0:#{Map.fetch!(@mail_types, reason)}",
        body: "",
        stationery: 62,
        checked: 4,
        deliver_at: now,
        money: 0,
        item_guid: 0
      }
    }
  end

  defp with_money(%Delivery{} = delivery, amount), do: %{delivery | attrs: %{delivery.attrs | money: amount}}
  defp with_body(%Delivery{} = delivery, body), do: %{delivery | attrs: %{delivery.attrs | body: body}}

  defp with_item(%Delivery{} = delivery, item) do
    receiver = delivery.attrs.receiver
    item = %{item | item: %{item.item | owner: receiver, contained: receiver}}
    %{delivery | item: item, attrs: %{delivery.attrs | item_guid: item.object.guid}}
  end

  defp guid_text(guid), do: guid |> Integer.to_string(16) |> String.pad_leading(16, "0")
end
