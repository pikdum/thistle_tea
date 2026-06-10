defmodule ThistleTea.Game.Network.Message.SmsgQuestgiverRequestItems do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTGIVER_REQUEST_ITEMS

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  defstruct [:npc_guid, :quest, completable: false, close_on_cancel: true]

  @impl ServerMessage
  def to_binary(%__MODULE__{npc_guid: npc_guid, quest: %Quest{} = q} = message) do
    <<npc_guid::little-size(64), q.id::little-size(32)>> <>
      q.title <>
      <<0>> <>
      q.request_items_text <>
      <<0, 0::little-size(32), emote(message)::little-size(32), close_on_cancel(message)::little-size(32),
        required_money(q)::little-size(32), length(q.required_items)::little-size(32)>> <>
      Enum.map_join(q.required_items, fn {_index, item_id, count} ->
        <<item_id::little-size(32), count::little-size(32), display_id(item_id)::little-size(32)>>
      end) <>
      <<2::little-size(32), completable_flag(message)::little-size(32), 4::little-size(32), 8::little-size(32)>>
  end

  defp emote(%__MODULE__{completable: true, quest: q}), do: q.complete_emote
  defp emote(%__MODULE__{quest: q}), do: q.incomplete_emote

  defp close_on_cancel(%__MODULE__{close_on_cancel: true}), do: 1
  defp close_on_cancel(%__MODULE__{}), do: 0

  defp completable_flag(%__MODULE__{completable: true}), do: 3
  defp completable_flag(%__MODULE__{}), do: 0

  defp required_money(%Quest{reward_money: money}) when money < 0, do: -money
  defp required_money(%Quest{}), do: 0

  defp display_id(item_id) do
    case ItemLoader.get_template(item_id) do
      %ItemTemplate{display_id: display_id} -> display_id
      _template -> 0
    end
  end
end
