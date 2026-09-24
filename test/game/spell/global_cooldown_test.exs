defmodule ThistleTea.Game.Spell.GlobalCooldownTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "gcd_duration/2" do
    test "ordinary casting haste and slows leave vanilla global cooldowns unchanged", %{caster: caster} do
      for amount <- [33, 100, -50], duration <- [1000, 1500, 2000] do
        assert Cooldowns.gcd_duration(with_auras(caster, [haste(amount)]), %{spell() | gcd_ms: duration}) == duration
      end
    end

    test "an accelerated cast can finish before its unchanged global cooldown", %{caster: caster} do
      spell = %{spell() | cast_time_ms: 1500}
      caster = with_auras(caster, [haste(33)]) |> Casting.start(spell, Target.self(1), 1000)
      assert caster.internal.casting.cast_time_ms == 1127
      completed = Casting.complete(caster, 2127)
      assert completed.internal.casting == nil
      assert Cooldowns.on_gcd?(completed, spell, 2499)
      refute Cooldowns.on_gcd?(completed, spell, 2500)
    end

    test "family modifiers alter the cooldown independently of casting haste", %{caster: caster} do
      caster = with_auras(caster, [modifier(-100), haste(100)])
      assert Cooldowns.gcd_duration(caster, spell()) == 1400
      assert Cooldowns.gcd_duration(caster, %{spell() | family_flags_0: 2}) == 1500
      assert Cooldowns.gcd_duration(caster, %{spell() | spell_family: 5}) == 1500

      percent = modifier(-20, :add_pct_modifier)
      assert Cooldowns.gcd_duration(with_auras(caster, [modifier(-100), percent]), spell()) == 1120
      assert Cooldowns.gcd_duration(with_auras(caster, [modifier(-2000)]), spell()) == 0
      assert Cooldowns.gcd_duration(with_auras(caster, [modifier(200)]), spell()) == 1700
    end

    test "nonplayers retain the unmodified spell timing", %{caster: caster} do
      caster = with_auras(caster, [modifier(-100), haste(100)])
      mob = %Mob{object: caster.object, unit: caster.unit, internal: caster.internal}
      assert Cooldowns.gcd_duration(mob, spell()) == 1500
    end

    test "category-only spells may receive modifiers but unrelated spells stay off the cooldown", %{caster: caster} do
      caster = with_auras(caster, [modifier(100)])
      assert Cooldowns.gcd_duration(caster, %{spell() | gcd_ms: 0}) == 100
      assert Cooldowns.gcd_duration(caster, %{spell() | gcd_ms: 0, gcd_category: 0}) == 0
      assert Cooldowns.gcd_duration(caster, %{spell() | gcd_ms: nil, gcd_category: 0}) == 0
    end
  end

  describe "trigger_gcd/3" do
    test "categories block their own spells, including members that do not start a cooldown", %{caster: caster} do
      first = spell()
      second = %{first | id: 2, gcd_category: 4, gcd_ms: 2000}
      member = %{first | id: 3, gcd_ms: 0}
      caster = caster |> Cooldowns.trigger_gcd(first, 1000) |> Cooldowns.trigger_gcd(second, 1200)

      assert Cooldowns.on_gcd?(caster, member, 2499)
      refute Cooldowns.on_gcd?(caster, member, 2500)
      assert Cooldowns.on_gcd?(caster, second, 3199)
      refute Cooldowns.on_gcd?(caster, second, 3200)
      refute Cooldowns.on_gcd?(caster, %{first | gcd_category: 0}, 1200)
      assert Cooldowns.trigger_gcd(caster, member, 1300) == caster
      assert {:error, :not_ready} = CastValidation.validate(caster, member, Target.self(1), nil, 2499)
      assert :ok = CastValidation.validate(caster, member, Target.self(1), nil, 2500)
    end

    test "a running cooldown retains its captured duration when its modifier expires", %{caster: caster} do
      caster = with_auras(caster, [%{modifier(-100) | expires_at: 1100}])
      caster = Cooldowns.trigger_gcd(caster, spell(), 1000)
      {caster, _events} = AuraLogic.expire_due(caster, 1100)
      assert Cooldowns.gcd_duration(caster, spell()) == 1500
      assert Cooldowns.on_gcd?(caster, spell(), 2399)
      refute Cooldowns.on_gcd?(caster, spell(), 2400)
    end
  end

  describe "cancel/2" do
    test "cancellation and interruption release only the preparing cast's category", %{caster: caster} do
      spell = %{spell() | cast_time_ms: 3000}
      other = %{spell | id: 2, gcd_category: 4}
      caster = caster |> Cooldowns.trigger_gcd(other, 1000) |> Casting.start(spell, Target.self(1), 1000)

      for stop <- [&Casting.cancel/2, &Casting.interrupt/2] do
        stopped = stop.(caster, 1100)
        assert stopped.internal.casting == nil
        refute Cooldowns.on_gcd?(stopped, spell, 1100)
        assert Cooldowns.on_gcd?(stopped, other, 1100)
        assert :ok = CastValidation.validate(stopped, spell, Target.self(1), nil, 1100)
      end
    end

    test "completed instant spells and active channels retain their cooldown", %{caster: caster} do
      completed = caster |> Casting.start(spell(), Target.self(1), 1000) |> Casting.complete(1000)
      assert completed.internal.casting == nil
      assert Cooldowns.on_gcd?(Casting.cancel(completed, 1100), spell(), 1100)

      channel = %{spell() | duration_ms: 5000, attributes: MapSet.new([:channeled])}
      active = Casting.start(caster, channel, Target.self(1), 1000)
      assert active.internal.casting.phase == :channel_tick
      stopped = Casting.cancel(active, 1100)
      assert stopped.internal.casting == nil
      assert Cooldowns.on_gcd?(stopped, channel, 1100)
    end

    test "a channel cancelled during preparation releases its cooldown", %{caster: caster} do
      channel = %{spell() | cast_time_ms: 3000, duration_ms: 5000, attributes: MapSet.new([:channeled])}
      stopped = caster |> Casting.start(channel, Target.self(1), 1000) |> Casting.cancel(1100)
      assert stopped.internal.casting == nil
      refute Cooldowns.on_gcd?(stopped, channel, 1100)
    end

    test "triggered casts neither start nor clear an existing cooldown", %{caster: caster} do
      caster = Cooldowns.trigger_gcd(caster, spell(), 1000)
      triggered = Casting.start_triggered(caster, spell(), Target.self(1), 1100, nil)
      assert triggered.internal.cooldowns == caster.internal.cooldowns
    end
  end

  describe "complete/2" do
    test "charged modifiers are retained on cancel and spent once after a successful cast", %{caster: caster} do
      charged = %{modifier(-100) | charges: 1}
      caster = with_auras(caster, [charged])
      assert Modifiers.consumable_holder_ids(caster, spell()) == [50]
      assert Modifiers.consumable_holder_ids(caster, %{spell() | gcd_category: 0, gcd_ms: 0}) == []
      cancelled = caster |> Casting.start(spell(), Target.self(1), 1000) |> Casting.cancel(1001)
      assert cancelled.unit.auras == [charged]

      completed = cancelled |> Casting.start(spell(), Target.self(1), 1100) |> Casting.complete(1100)
      assert completed.unit.auras == []
      assert Cooldowns.on_gcd?(completed, spell(), 2499)
      refute Cooldowns.on_gcd?(completed, spell(), 2500)
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
        player: %Player{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0},
        internal: %Internal{world: WorldRef.open(451)}
      }
    }
  end

  defp spell do
    %Spell{
      id: 100,
      spell_family: 6,
      family_flags_0: 1,
      gcd_category: 133,
      gcd_ms: 1500,
      effects: [%Effect{index: 0, type: :heal, base_points: 10, implicit_target_a: :caster}]
    }
  end

  defp with_auras(caster, auras), do: %{caster | unit: %{caster.unit | auras: auras}}

  defp haste(amount),
    do: %Holder{spell: %Spell{id: 60}, caster_guid: 1, auras: [%Aura{type: :mod_casting_speed, amount: amount}]}

  defp modifier(amount, type \\ :add_flat_modifier),
    do: %Holder{
      spell: %Spell{id: 50, spell_family: 6},
      auras: [%Aura{type: type, amount: amount, misc_value: 21, class_mask: 1}]
    }
end
