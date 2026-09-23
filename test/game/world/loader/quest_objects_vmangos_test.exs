defmodule ThistleTea.Game.World.Loader.QuestObjectsVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Goober
  alias ThistleTea.Game.World.Loader.EventScript
  alias ThistleTea.Game.World.Loader.PageText

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "preloads page chains and event commands used by quest objects" do
      assert :ok = PageText.load_all()
      assert :ok = EventScript.load_all()
      assert %{text: text, next_page: next_page} = PageText.get(358)
      assert text =~ "Elune"
      assert next_page > 0
      assert %{text: next_text} = PageText.get(next_page)
      assert is_binary(next_text)
      assert [_ | _] = steps = EventScript.get(663)
      assert Enum.any?(steps, &(&1.command == :talk))
      assert EventScript.get(-1) == []
    end
  end

  describe "configuration/1" do
    test "decodes quest pages, timed animations and consumable spell objects" do
      page =
        Mangos.Repo.get_by!(Mangos.GameObjectTemplate, entry: 17_188)
        |> GameObjectTemplate.build()
        |> Goober.configuration()

      assert page.quest_id == 953
      assert page.page_id == 358

      relic =
        Mangos.Repo.get_by!(Mangos.GameObjectTemplate, entry: 153_556)
        |> GameObjectTemplate.build()
        |> Goober.configuration()

      assert relic.auto_close_ms == 3_000
      assert relic.cooldown_ms == 10_000
      assert relic.custom_animation? and relic.consumable?

      geyser =
        Mangos.Repo.get_by!(Mangos.GameObjectTemplate, entry: 181_598)
        |> GameObjectTemplate.build()
        |> Goober.configuration()

      assert geyser.spell_id == 29_518
      assert geyser.auto_close_ms == 1_000 and geyser.consumable?
    end
  end
end
