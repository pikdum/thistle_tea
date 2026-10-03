defmodule ThistleTea.Game.Core.GameEvent.MinionsOfOmenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.MinionsOfOmen
  alias ThistleTea.Game.Core.GameEvent.Rule

  describe "launched/2" do
    test "the third firework brings the minions and the twentieth calls Omen" do
      assert Rule.for_event(43) == MinionsOfOmen
      {watch, calls} = launch(%MinionsOfOmen{}, 2, 0)
      refute MinionsOfOmen.driven(watch)[43]
      assert calls == []

      {watch, calls} = launch(watch, 1, 0)
      assert MinionsOfOmen.driven(watch)[43]
      assert calls == []

      {watch, []} = launch(watch, 16, 0)
      {watch, true} = MinionsOfOmen.launched(watch, 0)
      assert %MinionsOfOmen{fireworks: 0, omen_out?: true} = watch
      assert {^watch, false} = MinionsOfOmen.launched(watch, 0)
    end

    test "a fallen Omen rests fifteen minutes before fireworks call him again" do
      {watch, [_called]} = launch(%MinionsOfOmen{}, 20, 0)
      watch = MinionsOfOmen.fell(watch, 1_000)
      assert MinionsOfOmen.driven(watch)[43]

      {watch, calls} = launch(watch, 25, 1_000 + 15 * 60_000 - 1)
      assert calls == []
      assert {_watch, true} = MinionsOfOmen.launched(watch, 1_000 + 15 * 60_000)
    end
  end

  describe "gone/1" do
    test "the minions leave with Omen, who may be called again at once if he never fell" do
      {watch, [_called]} = launch(%MinionsOfOmen{}, 20, 0)
      watch = MinionsOfOmen.gone(watch)
      refute MinionsOfOmen.driven(watch)[43]

      assert {_watch, [19]} = launch(watch, 20, 0)
    end
  end

  defp launch(watch, count, now) do
    Enum.reduce(0..(count - 1)//1, {watch, []}, fn index, {watch, calls} ->
      {watch, called?} = MinionsOfOmen.launched(watch, now)
      {watch, if(called?, do: calls ++ [index], else: calls)}
    end)
  end
end
