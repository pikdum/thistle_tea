defmodule ThistleTea.Game.Core.Creature.GuardPostTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Creature.GuardPost

  describe "take/2" do
    test "accepts the first call at any monotonic time" do
      assert {:ok, %GuardPost{charges: 9}} = GuardPost.take(%GuardPost{}, -576_460_000_000)
    end

    test "spends a charge and refuses calls for ten seconds" do
      {:ok, post} = GuardPost.take(%GuardPost{}, 1_000)
      assert post.charges == 9

      assert {:denied, ^post} = GuardPost.take(post, 10_999)
      assert {:ok, %GuardPost{charges: 8}} = GuardPost.take(post, 11_000)
    end

    test "runs dry and regains a charge each minute" do
      {:ok, post} = GuardPost.take(%GuardPost{charges: 1, recharged_at: 0}, 0)

      assert post.charges == 0
      assert {:denied, _post} = GuardPost.take(post, 59_999)
      assert {:ok, %GuardPost{charges: 0}} = GuardPost.take(post, 60_000)
    end
  end

  describe "recharge/2" do
    test "regains whole minutes and keeps the remainder" do
      post = GuardPost.recharge(%GuardPost{charges: 3, recharged_at: 0}, 150_000)
      assert %GuardPost{charges: 5, recharged_at: 120_000} = post
    end

    test "never exceeds ten charges" do
      assert %GuardPost{charges: 10, recharged_at: 900_000} =
               GuardPost.recharge(%GuardPost{charges: 8, recharged_at: 0}, 900_000)
    end
  end

  describe "guard/2" do
    test "sends each side's guard or none" do
      assert GuardPost.guard(87, :alliance) == 68
      assert GuardPost.guard(87, :horde) == nil
      assert GuardPost.guard(35, :horde) == 4624
      assert GuardPost.guard(12, :alliance) == nil
      refute GuardPost.posted?(12)
      assert GuardPost.posted?(87)
    end
  end

  describe "text_id/3" do
    test "prefers the model's race over the faction" do
      assert GuardPost.text_id(87, 12, 55) == 4564
      assert GuardPost.text_id(87, 12, nil) == 4403
      assert GuardPost.text_id(87, 999, nil) == nil
    end

    test "has Razor Hill civilians call the grunts" do
      assert GuardPost.text_id(362, 126, 185) == 4558
    end
  end
end
