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
      %Mangos.NpcText{} = row -> text_groups(row)
      _ -> nil
    end
  end

  defp cache(text_id, groups) do
    :ets.insert(__MODULE__, {text_id, groups})
    groups
  end

  defp text_groups(npc_text) do
    Enum.map(0..7, fn i ->
      %{
        text_0: Map.get(npc_text, String.to_atom("text#{i}_0")),
        text_1: Map.get(npc_text, String.to_atom("text#{i}_1")),
        lang: Map.get(npc_text, String.to_atom("lang#{i}")),
        prob: Map.get(npc_text, String.to_atom("prob#{i}")),
        em_0_delay: Map.get(npc_text, String.to_atom("em#{i}_0_delay")),
        em_0: Map.get(npc_text, String.to_atom("em#{i}_0")),
        em_1_delay: Map.get(npc_text, String.to_atom("em#{i}_1_delay")),
        em_1: Map.get(npc_text, String.to_atom("em#{i}_1")),
        em_2_delay: Map.get(npc_text, String.to_atom("em#{i}_2_delay")),
        em_2: Map.get(npc_text, String.to_atom("em#{i}_2"))
      }
    end)
  end
end
