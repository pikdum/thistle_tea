defmodule ThistleTea.Game.Spell.CooldownsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns

  defp entity do
    %Mob{object: %Object{guid: 1}, internal: %Internal{}}
  end

  describe "start/3" do
    test "tracks a spell cooldown until it expires" do
      spell = %Spell{id: 2136, recovery_time_ms: 8_000}

      entity = Cooldowns.start(entity(), spell, 1_000)

      assert Cooldowns.ready_at(entity, spell) == 9_000
      assert Cooldowns.on_cooldown?(entity, spell, 1_000)
      assert Cooldowns.on_cooldown?(entity, spell, 8_999)
      refute Cooldowns.on_cooldown?(entity, spell, 9_000)
    end

    test "leaves state untouched for spells without cooldowns" do
      spell = %Spell{id: 133}

      entity = Cooldowns.start(entity(), spell, 1_000)

      assert entity.internal.cooldowns == %{}
      refute Cooldowns.on_cooldown?(entity, spell, 1_000)
    end

    test "category cooldown is shared between spells of the same category" do
      potion = %Spell{id: 439, category: 4, category_recovery_time_ms: 60_000}
      other_potion = %Spell{id: 440, category: 4, category_recovery_time_ms: 60_000}

      entity = Cooldowns.start(entity(), potion, 1_000)

      assert Cooldowns.on_cooldown?(entity, other_potion, 30_000)
      refute Cooldowns.on_cooldown?(entity, other_potion, 61_000)
    end

    test "category cooldown blocks members without their own category cooldown" do
      potion = %Spell{id: 439, category: 4, category_recovery_time_ms: 60_000}
      drink = %Spell{id: 430, category: 4}

      entity = Cooldowns.start(entity(), potion, 1_000)

      assert Cooldowns.on_cooldown?(entity, drink, 30_000)
      refute Cooldowns.on_cooldown?(entity, drink, 61_000)
      assert Cooldowns.ready_at(entity, drink) == 61_000
    end

    test "prunes expired entries when a new cooldown starts" do
      first = %Spell{id: 1, recovery_time_ms: 1_000}
      second = %Spell{id: 2, recovery_time_ms: 1_000}

      entity =
        entity()
        |> Cooldowns.start(first, 0)
        |> Cooldowns.start(second, 5_000)

      assert entity.internal.cooldowns == %{2 => 6_000}
    end
  end

  describe "client_cooldown_ms/1" do
    test "returns the longest of spell and category cooldowns" do
      assert Cooldowns.client_cooldown_ms(%Spell{recovery_time_ms: 8_000}) == 8_000
      assert Cooldowns.client_cooldown_ms(%Spell{category_recovery_time_ms: 60_000}) == 60_000

      assert Cooldowns.client_cooldown_ms(%Spell{recovery_time_ms: 8_000, category_recovery_time_ms: 60_000}) ==
               60_000

      assert Cooldowns.client_cooldown_ms(%Spell{}) == 0
    end
  end
end
