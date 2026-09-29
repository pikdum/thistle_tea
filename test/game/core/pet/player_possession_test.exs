defmodule ThistleTea.Game.Core.Pet.PlayerPossessionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Change
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.PlayerPossession
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Input
  alias ThistleTea.Game.World.Entity.Player.Movement

  setup [:character]

  describe "sync/2" do
    test "lethal damage releases control through the health transition", %{character: character} do
      {character, _} = change(character, [holder(2)], :applied)
      dead = Entity.take_damage(character, 100, 1)
      assert dead.unit.health == 0
      assert dead.internal.possession == nil
      assert dead.unit.faction_template == 1
      assert Enum.any?(dead.internal.events, &is_struct(&1, Effects.ControlReleased))
    end

    test "possession stops casting and attacks and grants an empty spell list", %{character: character} do
      character =
        character |> BT.enable_auto_attack(%TargetRef{guid: 99}) |> put_in([Access.key(:unit), Access.key(:target)], 99)

      character = put_in(character.internal.casting, %Cast{spell: %Spell{id: 133}})
      {possessed, events} = change(character, [holder(2)], :applied)

      assert PlayerPossession.controller(possessed) == 2
      assert possessed.unit.charmed_by == 2
      assert possessed.unit.faction_template == 2
      assert Bitwise.band(possessed.unit.flags, 0x01000000) != 0
      assert possessed.unit.target == 0
      assert possessed.internal.casting == nil
      refute possessed.internal.blackboard.combat.auto_attacking

      assert Enum.any?(
               events,
               &match?(%Effects.ControlGranted{source_guid: 2, target_guid: 1, kind: :possession, spells: []}, &1)
             )

      assert Enum.any?(events, &match?(%Effects.ClientControlChanged{allow_movement?: false}, &1))
      assert PlayerPossession.sync(possessed, 1) == {possessed, []}
    end

    test "every removal cause restores faction without restoring unrelated flags", %{character: character} do
      for cause <- [:expired, :dispelled, :death, :removed, :cancelled] do
        {possessed, _} = change(character, [holder(2)], :applied)
        possessed = put_in(possessed.unit.flags, Bitwise.bor(possessed.unit.flags, 0x1000))
        {restored, events} = change(possessed, [], cause)
        assert restored.internal.possession == nil
        assert restored.unit.faction_template == 1
        assert restored.unit.charmed_by == 0
        assert restored.unit.flags == 0x1008
        assert Enum.count(events, &is_struct(&1, Effects.ControlReleased)) == 1
        assert Enum.any?(events, &match?(%Effects.ClientControlChanged{allow_movement?: true}, &1))
        assert PlayerPossession.sync(restored, 2) == {restored, []}
      end
    end

    test "replacing controllers preserves the original faction", %{character: character} do
      {first, _} = change(character, [holder(2)], :applied)
      {second, events} = change(first, [holder(3)], :applied)
      assert PlayerPossession.controller(second) == 3
      assert second.internal.possession.original_faction_template == 1
      assert Enum.any?(events, &match?(%Effects.ControlReleased{source_guid: 2}, &1))
      {restored, _} = change(second, [], :removed)
      assert restored.unit.faction_template == 1
    end

    test "self possession does not acquire control", %{character: character} do
      {unchanged, events} = change(character, [holder(1)], :applied)
      refute PlayerPossession.active?(unchanged)
      refute Enum.any?(events, &is_struct(&1, Effects.ControlGranted))
    end

    test "creature charm uses AI without a player controller", %{character: character} do
      caster = Guid.from_low_guid(:mob, 1, 1)
      charm = %{holder(caster) | auras: [%Aura{type: :mod_charm}]}
      {controlled, events} = change(character, [charm], :applied)
      assert PlayerPossession.charmed?(controlled)
      refute PlayerPossession.manually_controlled?(controlled)
      assert controlled.unit.flags == 0
      refute Enum.any?(events, &is_struct(&1, Effects.ControlGranted))
      {released, events} = change(controlled, [], :removed)
      assert released.unit.flags == 8
      refute Enum.any?(events, &is_struct(&1, Effects.ControlReleased))
      {uncontrolled, _events} = change(character, [holder(caster)], :applied)
      refute PlayerPossession.active?(uncontrolled)
    end

    test "release cannot restore movement while fear remains", %{character: character} do
      fear = %{holder(3) | spell: %Spell{id: 5782}, auras: [%Aura{type: :mod_fear}]}
      {possessed, _} = change(character, [holder(2), fear], :applied)
      {restored, events} = change(possessed, [fear], :removed)
      refute PlayerPossession.active?(restored)
      refute Movement.accepts_input?(restored)
      refute Enum.any?(events, &match?(%Effects.ClientControlChanged{allow_movement?: true}, &1))
    end
  end

  describe "validate/3" do
    test "checks the rank's level cap and refuses existing possession", %{character: character} do
      spell = %Spell{
        id: 605,
        spell_level: 30,
        max_level: 30,
        effects: [
          %Effect{type: :apply_aura, aura: :mod_possess, base_points: 31, base_dice: 1, real_points_per_level: 1.0}
        ]
      }

      assert PlayerPossession.validate(character, spell, %{level: 32}) == :ok
      assert PlayerPossession.validate(character, spell, %{level: 33}) == {:error, :highlevel}
      assert PlayerPossession.validate(character, spell, %{level: 32, unit_flags: 0x01000000}) == {:error, :charmed}
      assert PlayerPossession.validate(character, spell, %{level: 32, charmed_by: 2}) == {:error, :charmed}
    end
  end

  describe "possession_guid/1" do
    test "ordinary charms leave the player's own movement authority intact", %{character: character} do
      ref = %EntityRef{guid: 2, entry: 0, spell_id: 10_912}
      assert character |> Companion.activate(:possession, ref) |> Companion.possession_guid() == 2
      assert character |> Companion.activate(:charm, ref) |> Companion.possession_guid() == nil
      pet = Companion.activate(character, :hunter_pet, ref)
      assert Companion.possession_guid(pet) == nil
      assert pet |> Companion.activate(:possession, ref) |> Companion.possession_guid() == 2
    end
  end

  describe "allowed?/2" do
    test "suspends gameplay input while keeping chat, queries, and acknowledgements available", %{character: character} do
      {character, _} = change(character, [holder(2)], :applied)
      state = %{character: character}

      for message <- [
            %Message.MsgMove{},
            %Message.CmsgAttackswing{},
            %Message.CmsgAttackstop{},
            %Message.CmsgCastSpell{},
            %Message.CmsgUseItem{},
            %Message.CmsgPetAction{},
            %Message.CmsgSetSelection{}
          ] do
        refute Input.allowed?(message, state)
        assert Input.handle(message, state) == state
      end

      for message <- [
            %Message.CmsgMessagechat{},
            %Message.CmsgNameQuery{},
            %Message.CmsgLogoutRequest{},
            %Message.CmsgSetActiveMover{},
            %Message.CmsgMoveNotActiveMover{},
            %Message.CmsgForceMoveRootAck{}
          ] do
        assert Input.allowed?(message, state)
      end

      refute Movement.accepts_input?(character)
      {released, _} = change(character, [], :removed)
      assert Input.allowed?(%Message.CmsgCastSpell{}, %{character: released})
      assert Movement.accepts_input?(released)
    end
  end

  describe "for_possession/3" do
    test "player possession exposes attack and no spells or pet reaction commands" do
      packet = Message.SmsgPetSpells.for_possession(1, [], 60_000)
      assert packet.action_bars == [0x07000002 | List.duplicate(0x01000000, 9)]
      assert packet.spells == []

      assert <<1::little-size(64), 60_000::little-size(32), 0::little-size(32), _::binary>> =
               Message.SmsgPetSpells.to_binary(packet)
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 60, faction_template: 1, flags: 8, auras: []},
        player: %Player{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0},
        internal: %Internal{}
      }
    }
  end

  defp holder(caster) do
    %Holder{
      spell: %Spell{id: 10_912},
      caster_guid: caster,
      caster_faction_template: 2,
      applied_at: 0,
      expires_at: 60_000,
      negative?: true,
      auras: [%Aura{type: :mod_possess}]
    }
  end

  defp change(character, holders, cause),
    do: Aura.transition(character, %Change{holders: holders, cause: cause, now: 0})
end
