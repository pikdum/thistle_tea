defmodule ThistleTea.Game.Entity.Logic.SelfResurrectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.SelfResurrection
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect

  setup [:build_character]

  describe "capture/2" do
    test "captures each rank and ignores expired protection", %{character: character} do
      for {aura_id, resurrection_id} <- [
            {20_707, 3026},
            {20_762, 20_758},
            {20_763, 20_759},
            {20_764, 20_760},
            {20_765, 20_761}
          ] do
        holder = %Holder{spell: %Spell{id: aura_id}, expires_at: 2_000}
        character = %{character | unit: %{character.unit | auras: [holder]}}
        assert SelfResurrection.capture(character, 1_999).player.self_res_spell == resurrection_id
        assert SelfResurrection.capture(character, 2_000).player.self_res_spell == 0
      end
    end

    test "retains protection through Spirit of Redemption's final death", %{character: character} do
      holder = %Holder{spell: %Spell{id: 27_827}, expires_at: 1_000}
      character = %{character | unit: %{character.unit | auras: [holder]}}
      assert SelfResurrection.capture(character, 1_000).player.self_res_spell == 3026
    end

    test "clears stale protection at the next unprotected death", %{character: character} do
      assert SelfResurrection.capture(character, 1_000).player.self_res_spell == 0
    end
  end

  describe "resurrect/3" do
    test "restores flat resources once and permits movement", %{character: character} do
      assert {:ok, resurrected, _events} = SelfResurrection.resurrect(character, soulstone(), 1_000)
      assert resurrected.unit.health == 400
      assert resurrected.unit.power1 == 700
      assert resurrected.unit.power2 == 0
      assert resurrected.unit.power4 == 100
      assert resurrected.player.self_res_spell == 0
      refute resurrected.internal.in_combat
      refute resurrected.internal.rooted?
      assert {:error, :unavailable} = SelfResurrection.resurrect(resurrected, soulstone(), 1_001)
      dead_again = Core.take_damage(resurrected, 400, 1_002)
      assert dead_again.player.self_res_spell == 0
    end

    test "clamps flat restoration to maximum resources", %{character: character} do
      character = %{character | unit: %{character.unit | max_health: 100, max_power1: 80}}
      assert {:ok, resurrected, _events} = SelfResurrection.resurrect(character, soulstone(), 1_000)
      assert resurrected.unit.health == 100
      assert resurrected.unit.power1 == 80
    end

    test "rejects living, released, missing and mismatched offers", %{character: character} do
      released = %{character | player: %{character.player | flags: 0x10}}
      living = %{character | unit: %{character.unit | health: 1}}
      missing = %{character | player: %{character.player | self_res_spell: 0}}
      mismatched = %{character | player: %{character.player | self_res_spell: 20_758}}

      for invalid <- [released, living, missing, mismatched] do
        assert {:error, :unavailable} = SelfResurrection.resurrect(invalid, soulstone(), 1_000)
      end
    end

    test "Reincarnation restores percentages and starts its shared cooldown", %{character: character} do
      character = shaman(character)
      spell = reincarnation()
      assert {:ok, resurrected, _events} = SelfResurrection.resurrect(character, spell, 1_000)
      assert resurrected.unit.health == 200
      assert resurrected.unit.power1 == 400
      assert Cooldowns.on_cooldown?(resurrected, spell, 3_600_999)
      assert Cooldowns.on_cooldown?(resurrected, %Spell{id: 20_608, category: 1161}, 3_600_999)
      refute Cooldowns.on_cooldown?(resurrected, spell, 3_601_000)
      refute SelfResurrection.available?(resurrected, spell, 2_000)
    end

    test "Improved Reincarnation modifies restoration and cooldown", %{character: character} do
      talent = %Holder{
        spell: %Spell{id: 16_209, spell_family: 11},
        auras: [
          %Aura{type: :add_flat_modifier, misc_value: 11, amount: -1_200_000, class_mask: 0},
          %Aura{type: :add_flat_modifier, misc_value: 8, amount: 20, class_mask: 0}
        ]
      }

      character = shaman(character)
      character = %{character | unit: %{character.unit | auras: [talent]}}
      spell = reincarnation()
      assert {:ok, resurrected, _events} = SelfResurrection.resurrect(character, spell, 1_000)
      assert resurrected.unit.health == 400
      assert resurrected.unit.power1 == 800
      assert Cooldowns.ready_at(resurrected, spell) == 2_401_000
    end

    test "rejects a forged Reincarnation offer without learning it", %{character: character} do
      character = %{character | player: %{character.player | self_res_spell: 21_169}}
      assert {:error, :unavailable} = SelfResurrection.resurrect(character, reincarnation(), 1_000)
    end
  end

  describe "release_spirit/3" do
    test "forfeits the self-resurrection offer", %{character: character} do
      {released, _events} = Death.release_spirit(character, [], 1_000)
      assert released.player.self_res_spell == 0
    end
  end

  defp build_character(_context) do
    character = %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        level: 60,
        health: 0,
        max_health: 1_000,
        power1: 0,
        max_power1: 2_000,
        power2: 100,
        power4: 0,
        max_power4: 100,
        auras: []
      },
      player: %Player{flags: 0, self_res_spell: 3026},
      internal: %Internal{spellbook: %{}, rooted?: false, in_combat: true},
      movement_block: %MovementBlock{run_speed: 7.0, base_run_speed: 7.0}
    }

    %{character: character}
  end

  defp soulstone do
    %Spell{
      id: 3026,
      effects: [%Effect{type: :self_resurrect, base_points: -401, base_dice: 1, die_sides: 1, misc_value: 700}]
    }
  end

  defp reincarnation do
    %Spell{
      id: 21_169,
      category: 1161,
      category_recovery_time_ms: 3_600_000,
      spell_family: 11,
      effects: [%Effect{type: :self_resurrect, base_points: 19, base_dice: 1, die_sides: 1}]
    }
  end

  defp shaman(character) do
    %{
      character
      | player: %{character.player | self_res_spell: 21_169},
        internal: %{character.internal | spellbook: %{20_608 => %Spell{id: 20_608}}}
    }
  end
end
