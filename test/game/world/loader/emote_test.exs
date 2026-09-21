defmodule ThistleTea.Game.World.Loader.EmoteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Emote
  alias ThistleTea.Game.World.Loader.Emote, as: Loader

  describe "load/3" do
    test "caches text mappings and animation persistence independently of database access" do
      table = :ets.new(:emotes, [:set, :public])
      animations = [%{id: 3, spec_proc: 0}, %{id: 10, spec_proc: 2}, %{id: 68, spec_proc: 1}]
      texts = [%{id: 101, emote: 3}, %{id: 34, emote: 10}, %{id: 59, emote: 68}]
      assert :ok = Loader.load(animations, texts, table)
      assert Loader.text(101, table) == %Emote{id: 3}
      assert Loader.text(34, table) == %Emote{id: 10, persistent?: true}
      assert Loader.text(59, table) == %Emote{id: 68, persistent?: true}
      assert Loader.text(9999, table) == nil
      assert Loader.animation(9999, table) == nil
    end
  end

  describe "load_all/1" do
    @tag :dbc_db
    test "loads vanilla text animations beyond the former partial mapping" do
      table = :ets.new(:emotes, [:set, :public])
      assert :ok = Loader.load_all(table)
      assert Loader.text(34, table) == %Emote{id: 10, persistent?: true}
      assert Loader.text(59, table) == %Emote{id: 68, persistent?: true}
      assert Loader.text(101, table) == %Emote{id: 3}
      assert :ets.info(table, :size) > 200
      assert Loader.animation(0, table) == %Emote{id: 0}
    end
  end
end
