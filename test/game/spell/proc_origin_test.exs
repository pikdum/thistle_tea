defmodule ThistleTea.Game.Spell.ProcOriginTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcOrigin

  describe "classify/2" do
    test "ordinary casts and effect-triggered spells can proc" do
      for context <- [%CastContext{}, %CastContext{triggered?: true}] do
        assert ProcOrigin.classify(damage_spell(), context) == :cast
      end
    end

    test "aura-triggered spells require an exception even for holders accepting procs" do
      spell = damage_spell()
      context = %CastContext{triggered?: true, triggered_by_aura?: true}
      assert ProcOrigin.classify(spell, context) == :suppressed
      holder = %Spell{proc_type_mask: 0x30000, attributes: MapSet.new([:can_proc_from_procs])}

      for type <- [:deal_harmful_spell, :take_harmful_spell] do
        refute Proc.eligible?(holder, spell, type, %{outcome: :normal, proc_origin: :suppressed})
      end

      spell = %{spell | attributes: MapSet.new([:not_a_proc])}
      assert ProcOrigin.classify(spell, context) == :aura_or_item

      assert Proc.eligible?(%{holder | attributes: MapSet.new()}, spell, :deal_harmful_spell, %{
               outcome: :normal,
               proc_origin: :aura_or_item
             })
    end

    test "positive item casts are suppressed and harmful item procs retain their origin" do
      item = %CastContext{cast_item_guid: 10}
      assert ProcOrigin.classify(%Spell{}, item) == :suppressed
      assert ProcOrigin.classify(%Spell{attributes: MapSet.new([:not_a_proc])}, item) == :suppressed
      assert ProcOrigin.classify(damage_spell(), item) == :cast
      assert ProcOrigin.classify(damage_spell(), %{item | triggered?: true}) == :aura_or_item
    end

    test "game objects cannot start ordinary proc chains" do
      context = %CastContext{caster_guid: Guid.from_low_guid(:game_object, 1, 10)}
      assert ProcOrigin.classify(damage_spell(), context) == :suppressed
    end

    test "channel, trap and class exceptions retain the aura-origin restriction" do
      exceptions = [
        %Spell{spell_family: 3, family_flags_0: 0x200000},
        %Spell{spell_family: 3, family_flags_0: 0x80},
        %Spell{spell_family: 5, family_flags_0: 0x20},
        %Spell{spell_family: 5, family_flags_0: 0x40},
        %Spell{spell_family: 9, family_flags_0: 0x4},
        %Spell{spell_family: 9, family_flags_0: 0x10},
        %Spell{spell_family: 6, family_flags_0: 0x80000},
        %Spell{spell_family: 6, family_flags_0: 0x2000000},
        %Spell{spell_family: 10, id: 20_424},
        %Spell{spell_family: 10, id: 25_997},
        %Spell{spell_family: 10, spell_icon: 25},
        %Spell{spell_family: 10, family_flags_0: 0x200000}
      ]

      for spell <- exceptions do
        origin = ProcOrigin.classify(spell, %CastContext{triggered?: true, triggered_by_aura?: true})
        assert origin == :aura_or_item
        holder = %Spell{proc_type_mask: 0x30000}
        context = %{outcome: :normal, proc_origin: origin}

        for type <- [:deal_harmful_spell, :take_harmful_spell] do
          refute Proc.eligible?(holder, spell, type, context)
          allowed = %{holder | attributes: MapSet.new([:can_proc_from_procs])}
          assert Proc.eligible?(allowed, spell, type, context)
        end
      end
    end

    test "unrelated family bits and icons are not exceptions" do
      for spell <- [
            %Spell{spell_family: 3, family_flags_1: 0x80},
            %Spell{spell_family: 10, spell_icon: 25, family_flags_1: 1},
            %Spell{spell_family: 0, id: 20_424},
            %Spell{spell_family: 6, family_flags_0: 0x400000}
          ] do
        assert ProcOrigin.classify(spell, %CastContext{triggered?: true, triggered_by_aura?: true}) == :suppressed
      end
    end
  end

  describe "eligible?/4" do
    test "target suppression preserves caster procs and applies to proc-enabled spells" do
      holder = %Spell{proc_type_mask: 0x30000, attributes: MapSet.new([:can_proc_from_procs])}
      trigger = %Spell{attributes: MapSet.new([:suppress_target_procs])}

      for origin <- [:cast, :aura_or_item] do
        context = %{outcome: :normal, proc_origin: origin}
        assert Proc.eligible?(holder, trigger, :deal_harmful_spell, context)
        refute Proc.eligible?(holder, trigger, :take_harmful_spell, context)
      end
    end
  end

  defp damage_spell do
    %Spell{dmg_class: 1, effects: [%Effect{type: :school_damage, base_points: 10}]}
  end
end
