defmodule ThistleTea.Game.Network.Message.SmsgQuestQueryResponse do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUEST_QUERY_RESPONSE

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Quest

  @hidden_rewards_flag 0x200

  defstruct [:quest]

  @impl ServerMessage
  def to_binary(%__MODULE__{quest: %Quest{} = q}) do
    <<
      q.id::little-size(32),
      q.method::little-size(32),
      q.level::little-size(32),
      q.zone_or_sort::little-signed-size(32),
      q.type::little-size(32),
      0::little-size(32),
      0::little-signed-size(32),
      0::little-size(32),
      0::little-size(32),
      q.next_quest_in_chain::little-size(32),
      visible_money(q)::little-signed-size(32),
      q.reward_money_max_level::little-size(32),
      q.reward_spell::little-size(32),
      q.src_item_id::little-size(32),
      q.flags::little-size(32)
    >> <>
      reward_items_binary(q) <>
      <<
        q.point_map_id::little-size(32),
        q.point_x::little-float-size(32),
        q.point_y::little-float-size(32),
        q.point_opt::little-size(32)
      >> <>
      q.title <>
      <<0>> <>
      q.objectives_text <>
      <<0>> <>
      q.details <>
      <<0>> <>
      q.end_text <>
      <<0>> <>
      objectives_binary(q) <>
      Enum.map_join(q.objective_texts, fn text -> text <> <<0>> end)
  end

  defp visible_money(%Quest{flags: flags}) when (flags &&& @hidden_rewards_flag) != 0, do: 0
  defp visible_money(%Quest{reward_money: money}), do: money

  defp reward_items_binary(%Quest{flags: flags}) when (flags &&& @hidden_rewards_flag) != 0 do
    <<0::size(32 * 20)>>
  end

  defp reward_items_binary(%Quest{} = q) do
    id_counts_binary(q.reward_items, 4) <> id_counts_binary(q.reward_choice_items, 6)
  end

  defp id_counts_binary(pairs, slots) do
    pairs
    |> Enum.concat(List.duplicate({0, 0}, slots - length(pairs)))
    |> Enum.map_join(fn {id, count} -> <<id::little-size(32), count::little-size(32)>> end)
  end

  defp objectives_binary(%Quest{objective_slots: slots}) do
    Enum.map_join(slots, fn slot ->
      <<
        encode_creature_or_go(slot.creature_or_go_id)::little-size(32),
        slot.creature_or_go_count::little-size(32),
        slot.item_id::little-size(32),
        slot.item_count::little-size(32)
      >>
    end)
  end

  defp encode_creature_or_go(id) when id < 0, do: -id ||| 0x80000000
  defp encode_creature_or_go(id), do: id
end
