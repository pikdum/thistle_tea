defmodule ThistleTea.Game.World.Loader.SpellLinkedAuraDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos.SpellEffectMod
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:barkskin_link]

  describe "load/1" do
    test "loads Barkskin's linked physical protection and melee penalty" do
      barkskin = SpellLoader.load(22_812)
      assert Enum.any?(barkskin.effects, &match?(%Effect{aura: :linked_aura, trigger_spell_id: 22_839}, &1))
      assert [child] = barkskin.linked_auras
      assert child.id == 22_839
      assert child.duration_ms == 15_000

      assert [%Effect{aura: :mod_melee_haste} = haste, %Effect{aura: :mod_damage_percent_taken} = protection] =
               child.effects

      assert Effect.roll(haste, 0) == -25
      assert Effect.roll(protection, 0) == -20
      assert protection.misc_value == 1
    end

    test "cuts cycles while retaining the linked spell's ordinary effects" do
      insert_link(22_839, 22_812)
      assert [child] = SpellLoader.load(22_812).linked_auras
      assert child.linked_auras == []
      assert Enum.any?(child.effects, &(&1.aura == :mod_melee_haste))
    end

    test "ignores missing linked definitions" do
      insert_link(22_812, 999_999)
      assert SpellLoader.load(22_812).linked_auras == []
    end

    test "Barkskin protects physical damage and casting until its complete expiry" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{class: 11, level: 60, health: 1_000, max_health: 1_000, base_melee_attack_time: 2_000, auras: []},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }

      barkskin = SpellLoader.load(22_812)
      wrath = SpellLoader.load(5176)
      {protected, _} = Aura.apply_spell(character, 1, 60, barkskin, 1_000)
      assert Combat.attack_speed_ms(protected) == 2_500
      assert Modifiers.integer_value(protected, wrath, :casting_time, wrath.cast_time_ms) == wrath.cast_time_ms + 1_000
      cast = Cast.new(wrath, Target.unit(2), 2_000)
      protected = %{protected | internal: %{protected.internal | casting: cast}}
      {damaged, 80, 0} = Core.take_damage_with_mitigation(protected, 100, 2_100, source: 2)
      assert damaged.internal.casting.ends_at == cast.ends_at
      {expired, _} = Aura.expire_due(damaged, 1_000 + barkskin.duration_ms)
      assert expired.unit.auras == []
      assert Combat.attack_speed_ms(expired) == 2_000
      assert Modifiers.integer_value(expired, wrath, :casting_time, wrath.cast_time_ms) == wrath.cast_time_ms
      expired = %{expired | internal: %{expired.internal | casting: cast}}
      {delayed, 100, 0} = Core.take_damage_with_mitigation(expired, 100, 2_100, source: 2)
      assert delayed.internal.casting.ends_at > cast.ends_at
    end

    test "loads general attack speed separately from melee-only haste" do
      crusader = SpellLoader.load(21_082)
      thunder_clap = SpellLoader.load(6343)
      assert Enum.any?(crusader.effects, &(&1.aura == :mod_attack_speed))
      assert Enum.any?(thunder_clap.effects, &(&1.aura == :mod_melee_haste))
    end
  end

  describe "build_spellbook/1" do
    test "retains the same links as individual loading" do
      assert SpellLoader.build_spellbook([22_812])[22_812] == SpellLoader.load(22_812)
    end
  end

  defp barkskin_link(_context), do: insert_link(22_812, 22_839)

  defp insert_link(id, child) do
    key = {:mods, id}
    previous = :ets.lookup(SpellEffectOverride, key)
    mod = %SpellEffectMod{id: id, effect_index: 1, effect: 6, effect_apply_aura_name: 192, effect_trigger_spell: child}
    :ets.insert(SpellEffectOverride, {key, %{1 => mod}})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
