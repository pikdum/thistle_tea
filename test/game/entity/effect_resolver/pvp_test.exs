defmodule ThistleTea.Game.Entity.EffectResolver.PvpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pvp, as: PvpLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  describe "spell_contacts/6" do
    test "successful Sap does not flag either player or enter combat" do
      spell = %Spell{
        spell_family: 8,
        family_flags_0: 0x80,
        attributes: MapSet.new([:not_in_combat, :only_peaceful_targets]),
        effects: [%Effect{type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}]
      }

      rows = %{2 => %{pvp?: true}}
      assert Pvp.spell_contacts(character(1), 1, 2, spell, :hit, metadata: &Map.get(rows, &1), now: 0) == []
      refute Spell.starts_combat?(spell)
      assert Spell.starts_combat?(spell, :miss)
    end

    @tag :dbc_db
    test "Beast Lore and Mind Vision do not flag their caster" do
      rows = %{2 => %{pvp?: true, in_combat: true, pvp_combat?: true, contested_pvp?: true}}

      for id <- [1462, 2096] do
        spell = SpellLoader.load(id)
        assert Pvp.spell_contacts(character(1), 1, 2, spell, :hit, metadata: &Map.get(rows, &1), now: 0) == []
      end
    end

    test "combat-free hostility flags both players without starting combat" do
      spell = %Spell{
        effects: [%Effect{type: :apply_aura, implicit_target_a: :target_enemy}],
        attributes: MapSet.new([:no_threat, :pvp_enabling])
      }

      rows = %{2 => %{pvp?: true}}
      effects = Pvp.spell_contacts(character(1), 1, 2, spell, :hit, metadata: &Map.get(rows, &1), now: 0)
      assert [%Effects.PvpContact{combat?: false} = attack, %Effects.PvpContact{combat?: false} = attacked] = effects
      caster = EventSink.emit(character(1), attack)
      victim = EventSink.emit(character(2), attacked)
      assert PvpLogic.active?(caster)
      assert PvpLogic.contested?(caster)
      assert PvpLogic.active?(victim)
      refute PvpLogic.contested?(victim)
      refute caster.internal.in_combat
      refute victim.internal.in_combat
      refute PvpLogic.combat?(caster)
      refute PvpLogic.contested?(PvpLogic.tick(caster, 30_000))
    end

    test "threat-on-miss spells flag and enter combat only on a miss" do
      spell = %Spell{
        effects: [%Effect{type: :apply_aura, implicit_target_a: :target_enemy}],
        attributes: MapSet.new([:threat_only_on_miss])
      }

      rows = %{2 => %{pvp?: true}}
      opts = [metadata: &Map.get(rows, &1), now: 0]
      assert Pvp.spell_contacts(character(1), 1, 2, spell, :hit, opts) == []

      assert [%Effects.PvpContact{combat?: true}, %Effects.PvpContact{combat?: true}] =
               Pvp.spell_contacts(character(1), 1, 2, spell, :miss, opts)
    end

    test "no-threat assistance flags without inheriting combat or contested status" do
      spell = %Spell{
        effects: [%Effect{type: :apply_aura, implicit_target_a: :target_ally}],
        attributes: MapSet.new([:no_threat])
      }

      rows = %{2 => %{pvp?: true, in_combat: true, pvp_combat?: true, contested_pvp?: true}}
      [effect] = Pvp.spell_contacts(character(1), 1, 2, spell, :hit, metadata: &Map.get(rows, &1), now: 0)
      caster = EventSink.emit(character(1), effect)
      assert PvpLogic.active?(caster)
      refute caster.internal.in_combat
      refute PvpLogic.contested?(caster)
    end

    test "party assistance in the second implicit target slot flags a PvP caster" do
      spell = %Spell{
        effects: [%Effect{type: :apply_aura, implicit_target_a: :any_unit, implicit_target_b: :party_around_target}],
        attributes: MapSet.new([:no_threat])
      }

      rows = %{2 => %{pvp?: true}}

      assert [%Effects.PvpContact{target_guid: 1, role: :assist}] =
               Pvp.spell_contacts(character(1), 1, 2, spell, :hit, metadata: &Map.get(rows, &1), now: 0)
    end

    test "no-threat assistance does not flag for a PvP creature" do
      mob = Guid.from_low_guid(:mob, 1, 1)

      spell = %Spell{
        effects: [%Effect{type: :heal, implicit_target_a: :target_ally}],
        attributes: MapSet.new([:no_threat])
      }

      rows = %{mob => %{unit_flags: 0x1000, in_combat: true}}
      effects = Pvp.spell_contacts(character(1), 1, mob, spell, :hit, metadata: &Map.get(rows, &1), now: 0)
      refute character(1) |> EventSink.emit(effects) |> PvpLogic.active?()
    end
  end

  describe "contacts/5" do
    test "a possessed player's combat flags the controller" do
      possession = %Possession{caster_guid: 3, spell_id: 605, original_faction_template: 1}
      victim = put_in(character(1).internal.possession, possession)
      rows = %{1 => %{owner_guid: 3}, 2 => %{pvp?: true}, 3 => %{pvp?: false}}

      assert [
               %Effects.PvpContact{target_guid: 3, role: :attack},
               %Effects.PvpContact{target_guid: 2, role: :attacked}
             ] =
               Pvp.contacts(victim, 1, 2, :attack, metadata: &Map.get(rows, &1), now: 0)
    end

    test "resolves a pet attack to both players and applies the owner's flags" do
      pet = Guid.from_low_guid(:pet, 1, 7)
      rows = %{pet => %{owner_guid: 1}, 1 => %{pvp?: false}, 2 => %{pvp?: true}}
      effects = Pvp.contacts(%{}, pet, 2, :attack, metadata: &Map.get(rows, &1), now: 0)
      assert [%Effects.PvpContact{target_guid: 1} = attack, %Effects.PvpContact{target_guid: 2} = attacked] = effects
      assert attack.other.player_guid == 2
      assert attacked.other.player_guid == 1
      assert attacked.other.pvp?
      owner = EventSink.emit(character(1), attack)
      assert PvpLogic.active?(owner)
      assert PvpLogic.contested?(owner)
      assert owner.internal.in_combat
      victim = EventSink.emit(character(2), attacked)
      assert PvpLogic.active?(victim)
      refute PvpLogic.contested?(victim)
    end

    test "helping another player's totem resolves its owner's PvP state" do
      totem = Guid.from_low_guid(:mob, 5925, 1)
      rows = %{totem => %{owner_guid: 2}, 2 => %{pvp?: true, contested_pvp?: true, in_combat: true}}
      effects = Pvp.contacts(character(1), 1, totem, :assist, metadata: &Map.get(rows, &1), now: 0)
      assert [%Effects.PvpContact{target_guid: 1, role: :assist} = effect] = effects
      caster = EventSink.emit(character(1), effect)
      assert PvpLogic.contested?(caster)
      assert caster.internal.in_combat
    end

    test "ordinary PvE and self assistance produce no PvP notifications" do
      mob = Guid.from_low_guid(:mob, 1, 1)
      rows = %{mob => %{unit_flags: 0}}
      assert Pvp.contacts(character(1), 1, mob, :attack, metadata: &Map.get(rows, &1), now: 0) == []
      flagged = PvpLogic.toggle(character(1), true, 0)
      assert Pvp.contacts(flagged, 1, 1, :assist, metadata: fn _ -> nil end, now: 0) == []
    end

    test "PvP-enabling creatures flag the aggressor without contested guards" do
      mob = Guid.from_low_guid(:mob, 1, 1)
      rows = %{mob => %{unit_flags: 0x1000}}
      [effect] = Pvp.contacts(character(1), 1, mob, :attack, metadata: &Map.get(rows, &1), now: 0)
      caster = EventSink.emit(character(1), effect)
      assert PvpLogic.active?(caster)
      refute PvpLogic.contested?(caster)
    end
  end

  defp character(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, flags: 8},
      player: %Player{flags: 0},
      internal: %Internal{}
    }
  end
end
