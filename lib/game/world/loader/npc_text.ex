defmodule ThistleTea.Game.World.Loader.NpcText do
  @moduledoc """
  ETS cache of npc_text rows from Mangos, translated into the text-group
  shape the npc-text-update packet needs.
  """
  alias ThistleTea.DB.Mangos

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get(text_id) when is_integer(text_id) and text_id > 0 do
    case :ets.lookup(__MODULE__, text_id) do
      [{^text_id, groups}] -> groups
      _ -> cache(text_id, load(text_id))
    end
  end

  def get(_text_id), do: nil

  defp load(text_id) do
    case Mangos.Repo.get(Mangos.NpcText, text_id) do
      %Mangos.NpcText{} = row -> text_groups(row, broadcast_texts(row))
      _ -> nil
    end
  end

  defp cache(text_id, groups) do
    :ets.insert(__MODULE__, {text_id, groups})
    groups
  end

  defp broadcast_texts(npc_text) do
    npc_text
    |> broadcast_text_ids()
    |> Enum.reject(&(&1 == 0))
    |> then(fn ids ->
      import Ecto.Query

      Mangos.BroadcastText
      |> where([bt], bt.entry in ^ids)
      |> Mangos.Repo.all()
      |> Map.new(fn row -> {row.entry, row} end)
    end)
  end

  defp broadcast_text_ids(npc_text) do
    Enum.map(0..7, fn i -> Map.get(npc_text, String.to_atom("broadcast_text_id#{i}")) || 0 end)
  end

  defp text_groups(npc_text, broadcast_texts) do
    Enum.map(0..7, fn i ->
      broadcast_text_id = Map.get(npc_text, String.to_atom("broadcast_text_id#{i}")) || 0
      broadcast_text = Map.get(broadcast_texts, broadcast_text_id)

      %{
        text_0: text(broadcast_text, :male_text),
        text_1: text(broadcast_text, :female_text),
        lang: integer(broadcast_text, :language_id),
        prob: Map.get(npc_text, String.to_atom("prob#{i}")),
        em_0_delay: integer(broadcast_text, :emote_delay1),
        em_0: integer(broadcast_text, :emote_id1),
        em_1_delay: integer(broadcast_text, :emote_delay2),
        em_1: integer(broadcast_text, :emote_id2),
        em_2_delay: integer(broadcast_text, :emote_delay3),
        em_2: integer(broadcast_text, :emote_id3)
      }
    end)
  end

  defp text(nil, _field), do: ""
  defp text(row, field), do: Map.get(row, field) || ""

  defp integer(nil, _field), do: 0
  defp integer(row, field), do: Map.get(row, field) || 0
end
