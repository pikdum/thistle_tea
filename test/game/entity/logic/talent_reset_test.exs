defmodule ThistleTea.Game.Entity.Logic.TalentResetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.TalentReset
  alias ThistleTea.Game.Entity.Logic.TalentReset, as: ResetPrice

  @month 30 * 24 * 60 * 60 * 1_000

  describe "purchase/3" do
    test "charges one gold, then five-gold increments up to fifty gold" do
      Enum.reduce([10_000 | Enum.to_list(50_000..500_000//50_000)] ++ [500_000], %TalentReset{}, fn cost, history ->
        assert ResetPrice.cost(history, -1_000) == cost
        assert {:ok, updated, 0} = ResetPrice.purchase(history, cost, -1_000)
        assert updated.last_reset_at == -1_000
        updated
      end)
    end

    test "does not change history when payment fails" do
      history = %TalentReset{multiplier: 5, last_reset_at: 0}
      assert {:error, :not_enough_money} = ResetPrice.purchase(history, 199_999, @month)
      assert ResetPrice.cost(history, @month) == 200_000
    end
  end

  describe "cost/2" do
    test "decays once per elapsed month with a ten-gold floor after the early resets" do
      history = %TalentReset{multiplier: 10, last_reset_at: -5_000}
      assert ResetPrice.cost(history, -5_000 + @month - 1) == 500_000
      assert ResetPrice.cost(history, -5_000 + @month) == 450_000
      assert ResetPrice.cost(history, -5_000 + 8 * @month) == 100_000
      assert ResetPrice.cost(history, -5_000 + 100 * @month) == 100_000
      assert ResetPrice.cost(history, -5_000 + @month) == 450_000
      assert {:ok, updated, 0} = ResetPrice.purchase(history, 450_000, -5_000 + @month)
      assert ResetPrice.cost(updated, -5_000 + @month) == 500_000
    end

    test "permits the initial price again after only one historical reset" do
      history = %TalentReset{multiplier: 1, last_reset_at: 0}
      assert ResetPrice.cost(history, @month - 1) == 50_000
      assert ResetPrice.cost(history, @month) == 10_000
      assert ResetPrice.cost(%TalentReset{multiplier: 2, last_reset_at: 0}, @month) == 100_000
    end
  end
end
