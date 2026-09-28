defmodule ThistleTea.Game.Entity.Logic.ObjectiveCarrierTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Invulnerability
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.GameObjectInteraction
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "apply_spell/5" do
    test "rejects a late carrier grant after protection or mounting and notifies the match", %{character: character} do
      for spell <- [aura(100, :school_immunity, misc_value: 127), aura(101, :mounted, misc_value: 1234)] do
        blocked = apply_spell(character, spell)
        {unchanged, effects} = Aura.apply_spell(blocked, 1, 60, flag(), 100)
        assert unchanged == blocked
        refute Invulnerability.carrier?(unchanged)
        assert [%Effects.BattlegroundFlagRemoved{guid: 1, team: :horde}] = drops(effects)
      end
    end

    test "positive school immunity interrupts objectives without requiring purge attributes", %{character: character} do
      carrier = apply_spell(character, flag())
      {protected, effects} = Aura.apply_spell(carrier, 1, 60, aura(100, :school_immunity, misc_value: 1), 100)

      refute Invulnerability.carrier?(protected)
      assert Aura.has_spell?(protected, 100)
      assert [%Effects.BattlegroundFlagRemoved{guid: 1, team: :horde, position: position}] = drops(effects)
      assert position == {1.0, 2.0, 3.0, 0.0}
      {removed, effects} = Aura.remove_spells(protected, [23_333], 101)
      assert removed == protected
      assert drops(effects) == []
    end

    test "negative school protection and charmed players retain objectives", %{character: character} do
      carrier = apply_spell(character, flag())
      hostile = %{aura(100, :school_immunity, misc_value: 127) | attributes: MapSet.new([:negative])}
      {protected, effects} = Aura.apply_spell(carrier, 2, 60, hostile, 100)
      assert Invulnerability.carrier?(protected)
      assert drops(effects) == []

      charmed = %{carrier | unit: %{carrier.unit | charmed_by: 2}}
      {protected, effects} = Aura.apply_spell(charmed, 1, 60, aura(100, :school_immunity, misc_value: 127), 100)
      assert Invulnerability.carrier?(protected)
      assert drops(effects) == []
    end

    test "mounting, concealment, and unattackable states remove the carrier once", %{character: character} do
      for type <- [:mounted, :mod_stealth, :mod_invisibility, :mod_unattackable] do
        carrier = apply_spell(character, flag())
        {changed, effects} = Aura.apply_spell(carrier, 1, 60, aura(100, type, misc_value: 1234), 100)
        refute Invulnerability.carrier?(changed)
        assert length(drops(effects)) == 1
      end
    end

    test "carrier refresh retains ownership while cancellation and death notify removal", %{character: character} do
      carrier = apply_spell(character, flag())
      {refreshed, effects} = Aura.apply_spell(carrier, 1, 60, flag(), 100)
      assert Invulnerability.carrier?(refreshed)
      assert drops(effects) == []
      {cancelled, effects} = Aura.cancel_spell(refreshed, 23_333, 101)
      refute Invulnerability.carrier?(cancelled)
      assert length(drops(effects)) == 1
      dead = Core.take_damage(carrier, 100, 100)
      refute Invulnerability.carrier?(dead)
      assert length(drops(dead.internal.events)) == 1
    end

    test "Silithyst removal clears faction visuals and emits one mound", %{character: character} do
      carrier =
        %{character | internal: %{character.internal | world: WorldRef.open(1)}}
        |> apply_spell(%{flag() | id: 29_519})
        |> apply_spell(aura(29_894, :dummy))

      {protected, effects} = Aura.apply_spell(carrier, 1, 60, aura(100, :school_immunity, misc_value: 127), 100)
      refute Aura.has_spell?(protected, 29_519)
      refute Aura.has_spell?(protected, 29_894)
      assert drops(effects) == []
      assert Enum.count(effects, &match?(%Effects.SummonGameObject{entry: 181_597}, &1)) == 1
    end

    test "existing immunity does not repeatedly interrupt unrelated aura updates", %{character: character} do
      protection = aura(100, :school_immunity, misc_value: 1)
      protected = apply_spell(character, protection)
      carrier = apply_spell(protected, flag())
      {updated, effects} = Aura.apply_spell(carrier, 1, 60, aura(101, :dummy), 100)
      assert Invulnerability.carrier?(updated)
      assert drops(effects) == []
    end
  end

  describe "receive/4" do
    test "friendly protection cannot force an objective drop and reports immunity", %{character: character} do
      carrier = apply_spell(character, flag())
      protection = aura(100, :school_immunity, misc_value: 1, implicit_target_a: :target_ally)
      {unchanged, effects} = SpellEffect.receive(carrier, 2, protection, 100)
      assert Invulnerability.carrier?(unchanged)
      refute Aura.has_spell?(unchanged, 100)
      assert [%Effects.SpellLogMiss{reason: :immune}] = effects
      assert {unchanged, []} == Aura.apply_spell(carrier, 2, 60, protection, 100)
    end
  end

  describe "validate/6" do
    test "rejects targeted protection before costs for self and remote carriers", %{character: character} do
      carrier = apply_spell(character, flag())
      protection = aura(100, :school_immunity, misc_value: 1, implicit_target_a: :target_ally)

      assert CastValidation.validate(carrier, protection, Target.self(1), nil, 100) == {:error, :target_aurastate}

      assert CastValidation.validate(
               character,
               protection,
               Target.self(2),
               %{invulnerability_interruptible?: true},
               100
             ) ==
               {:error, :target_aurastate}

      triggered = %{
        protection
        | triggers_school_immunity?: true,
          effects: [%Effect{index: 0, type: :clear_threat, implicit_target_a: :target_ally}]
      }

      assert CastValidation.validate(carrier, triggered, Target.self(1), nil, 100) == {:error, :target_aurastate}
      bypass = %{protection | attributes: MapSet.new([:ignore_caster_and_target_restrictions])}
      refute Invulnerability.blocks_protection?(carrier, bypass)
    end
  end

  describe "prepare_battleground_use/2" do
    test "rejects total immunity, mounts, death, and loss of control", %{character: character} do
      protected =
        character
        |> apply_spell(aura(100, :school_immunity, misc_value: 1))
        |> apply_spell(aura(101, :school_immunity, misc_value: 126))

      assert Invulnerability.total?(protected)
      assert {:error, :not_interactable} = GameObjectInteraction.prepare_battleground_use(protected, 100)

      for type <- [:mounted, :mod_stun, :mod_confuse, :mod_fear, :feign_death, :mod_possess] do
        blocked = apply_spell(character, aura(100, type, misc_value: 1234))
        refute GameObjectInteraction.battleground_allowed?(blocked)
      end

      refute GameObjectInteraction.battleground_allowed?(%{character | unit: %{character.unit | health: 0}})
    end

    test "allows roots and partial immunity and removes concealment before pickup", %{character: character} do
      for type <- [:mod_root, :school_immunity] do
        allowed = apply_spell(character, aura(100, type, misc_value: 1))
        assert GameObjectInteraction.battleground_allowed?(allowed)
      end

      hidden =
        character |> apply_spell(aura(100, :mod_stealth)) |> apply_spell(aura(101, :mod_invisibility, misc_value: 1))

      assert {:ok, visible} = GameObjectInteraction.prepare_battleground_use(hidden, 100)
      refute Aura.has_spell?(visible, 100)
      refute Aura.has_spell?(visible, 101)
    end
  end

  defp drops(effects), do: Enum.filter(effects, &is_struct(&1, Effects.BattlegroundFlagRemoved))

  defp apply_spell(character, spell) do
    {character, _effects} = Aura.apply_spell(character, 1, 60, spell, 0)
    character
  end

  defp flag, do: %{aura(23_333, :effect_immunity, misc_value: :bind) | aura_interrupt_flags: 0x003A0000}

  defp aura(id, type, opts \\ []) do
    effect = struct!(%Effect{index: 0, type: :apply_aura, aura: type, implicit_target_a: :caster}, opts)
    %Spell{id: id, school: :holy, duration_ms: 10_000, effects: [effect]}
  end

  defp character(_context) do
    %{
      character: %Character{
        id: 1,
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{race: 1, level: 60, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
        internal: %Internal{world: WorldRef.instance(489, 7)},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}}
      }
    }
  end
end
