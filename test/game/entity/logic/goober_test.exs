defmodule ThistleTea.Game.Entity.Logic.GooberTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.GameObjectActions
  alias ThistleTea.Game.Entity.Logic.Goober
  alias ThistleTea.Game.Entity.Logic.QuestLog

  setup [:object]

  describe "quest_allowed?/3" do
    test "requires an incomplete known quest and ignores nonpositive or unknown requirements" do
      {:ok, log} = QuestLog.add(%{}, 1)
      assert Goober.quest_allowed?(log, 1, true)
      refute Goober.quest_allowed?(%{}, 1, true)

      for status <- [:complete, :failed] do
        {:ok, changed} = QuestLog.update(log, 1, &%{&1 | status: status})
        refute Goober.quest_allowed?(changed, 1, true)
      end

      for id <- [-1, 0], do: assert(Goober.quest_allowed?(%{}, id, true))
      assert Goober.quest_allowed?(%{}, 1, false)
    end
  end

  describe "use/3" do
    test "failed requirements permit reading while honoring the use cooldown", %{object: object} do
      assert {:read_only, waiting} = Goober.use(object, false, 0)
      assert waiting.game_object.state == 1
      assert waiting.internal.events == []
      assert {:unavailable, ^waiting} = Goober.use(waiting, true, 4_999)
      assert {:activated, _} = Goober.use(waiting, true, 5_000)
    end

    test "activation uses auto-close time and serializes repeated use", %{object: object} do
      assert {:activated, active} = Goober.use(object, true, 0)
      assert active.game_object.state == 0
      assert active.game_object.flags == 5
      assert [%Effects.FinishGameObjectUse{revision: 1, delay_ms: 3_000}] = active.internal.events
      assert {:unavailable, ^active} = Goober.use(active, true, 10_000)
      ready = Goober.finish(active, 1)
      assert ready.game_object.state == 1
      assert ready.game_object.flags == 4
      assert {:activated, _} = Goober.use(ready, true, 3_000)
    end

    test "custom animations retain ready state and in-use flags", %{template: template} do
      template = %{template | data: List.replace_at(template.data, 4, 1)}
      object = GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0})
      {:activated, active} = Goober.use(object, true, 0)
      assert active.game_object.state == 1
      assert active.game_object.flags == 5
      assert Enum.any?(active.internal.events, &match?(%Effects.GameObjectCustomAnimation{animation: 0}, &1))
    end

    test "inert objects cannot consume their use cooldown", %{object: object} do
      object = GameObjectActions.apply(object, 16, 1)
      assert {:unavailable, ^object} = Goober.use(object, true, 0)
    end
  end

  describe "finish/2" do
    test "stale timers cannot reset a newer activation", %{object: object} do
      {:activated, first} = Goober.use(object, true, 0)
      {:activated, second} = first |> GameObjectActions.reset() |> Goober.use(true, 3_000)
      assert Goober.finish(second, 1) == second
      refute Goober.finish(second, second.internal.object_action.revision).internal.object_action.active?
    end

    test "consumables and owned summons become unavailable before removal", %{object: object} do
      consumable = %{object | internal: %{object.internal | goober: %{object.internal.goober | consumable?: true}}}
      summoned = %{object | game_object: %{object.game_object | created_by: 7}}

      for entity <- [consumable, summoned] do
        {:activated, active} = Goober.use(entity, true, 0)
        finished = Goober.finish(active, 1)
        assert finished.internal.goober.depleted?
        assert Enum.any?(finished.internal.events, &match?(%Effects.RemoveSelf{}, &1))
        assert {:unavailable, ^finished} = Goober.use(finished, true, 10_000)
      end
    end
  end

  defp object(_context) do
    data = List.duplicate(0, 24) |> List.replace_at(3, 3 * 65_536 + 1) |> List.replace_at(6, 5)
    template = %GameObjectTemplate{entry: 1, type: 10, size: 1.0, flags: 4, data: data}
    %{template: template, object: GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0})}
  end
end
