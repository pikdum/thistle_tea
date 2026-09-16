defmodule ThistleTea.Game.Entity.Logic.DiminishingReturnsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.DiminishingReturns
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  defp target, do: %Character{object: %Object{guid: 2}, internal: %Internal{}}

  defp context do
    %CastContext{caster_guid: 1, caster_type: :player, target_hostile?: true}
  end

  defp holder(now, mechanic \\ 12) do
    %Holder{
      spell: %Spell{id: 56, mechanic: mechanic},
      applied_at: now,
      expires_at: now + 8_000,
      negative?: true
    }
  end

  describe "apply/4" do
    test "advances through full, half, quarter, and immunity" do
      entity =
        Enum.reduce([8_000, 4_000, 2_000], target(), fn duration, entity ->
          {:ok, entity, applied} = DiminishingReturns.apply(entity, holder(1_000), context(), 1_000)
          assert applied.expires_at == 1_000 + duration
          assert applied.diminishing_group == :controlled_stun
          entity
        end)

      assert {:immune, ^entity} = DiminishingReturns.apply(entity, holder(2_000), context(), 2_000)
    end

    test "keeps active control diminished even after fifteen seconds" do
      {:ok, entity, _holder} = DiminishingReturns.apply(target(), holder(0), context(), 0)
      {:ok, _entity, applied} = DiminishingReturns.apply(entity, holder(60_000), context(), 60_000)
      assert applied.expires_at == 64_000
    end

    test "uses independent groups and excludes friendly or permanent auras" do
      {:ok, entity, _} = DiminishingReturns.apply(target(), holder(0), context(), 0)
      {:ok, _, root} = DiminishingReturns.apply(entity, holder(0, 7), context(), 0)
      assert root.expires_at == 8_000

      for incoming <- [%{holder(0) | negative?: false}, %{holder(0) | expires_at: -1}] do
        assert {:ok, ^entity, ^incoming} = DiminishingReturns.apply(entity, incoming, context(), 0)
      end

      incoming = holder(0)
      friendly = %{context() | target_hostile?: false}
      assert {:ok, ^entity, ^incoming} = DiminishingReturns.apply(entity, incoming, friendly, 0)
    end

    test "stuns diminish creatures but roots require PvP" do
      mob = %Mob{object: %Object{guid: 2}, internal: %Internal{}}
      {:ok, mob, _} = DiminishingReturns.apply(mob, holder(0), context(), 0)
      {:ok, _, stun} = DiminishingReturns.apply(mob, holder(0), context(), 0)
      assert stun.expires_at == 4_000
      root = holder(0, 7)
      assert {:ok, ^mob, ^root} = DiminishingReturns.apply(mob, root, context(), 0)

      npc_context = %{context() | caster_type: :mob}
      player = target()
      assert {:ok, ^player, ^root} = DiminishingReturns.apply(player, root, npc_context, 0)
    end

    test "player pets participate in PvP groups" do
      pet = %Mob{object: %Object{guid: 2}, internal: %Internal{pet: %Pet{owner_guid: 3}}}
      pet_context = %{context() | caster_type: :mob, caster_owner_guid: 4}
      {:ok, pet, _} = DiminishingReturns.apply(pet, holder(0, 7), pet_context, 0)
      {:ok, _, root} = DiminishingReturns.apply(pet, holder(1_000, 7), pet_context, 1_000)
      assert root.expires_at == 5_000
    end

    test "self casts are exempt unless reflected" do
      self_context = %{context() | caster_guid: 2}
      target = target()
      holder = holder(0)
      assert {:ok, ^target, ^holder} = DiminishingReturns.apply(target, holder, self_context, 0)

      reflected = %{self_context | reflected_by_guid: 3}
      {:ok, target, _} = DiminishingReturns.apply(target, holder, reflected, 0)
      assert target.internal.diminishing_returns.controlled_stun.applications == 1
    end

    test "permanent holders stay exempt with negative monotonic timestamps" do
      target = target()
      holder = %{holder(-50_000) | expires_at: -1}
      assert {:ok, ^target, ^holder} = DiminishingReturns.apply(target, holder, context(), -50_000)
    end
  end

  describe "reconcile/4" do
    test "recovers fifteen seconds after the final group holder leaves" do
      {:ok, entity, first} = DiminishingReturns.apply(target(), holder(0), context(), 0)
      {:ok, entity, second} = DiminishingReturns.apply(entity, holder(1_000), context(), 1_000)
      entity = DiminishingReturns.reconcile(entity, [first, second], [second], 5_000)
      assert entity.internal.diminishing_returns.controlled_stun.reset_at == nil

      entity = DiminishingReturns.reconcile(entity, [second], [], 6_000)
      assert entity.internal.diminishing_returns.controlled_stun.reset_at == 21_000
      {:ok, _, reduced} = DiminishingReturns.apply(entity, holder(20_999), context(), 20_999)
      assert reduced.expires_at == 22_999
      {:ok, _, recovered} = DiminishingReturns.apply(entity, holder(21_000), context(), 21_000)
      assert recovered.expires_at == 29_000
    end

    test "replacing a holder keeps the group active" do
      {:ok, entity, first} = DiminishingReturns.apply(target(), holder(0), context(), 0)
      {:ok, entity, second} = DiminishingReturns.apply(entity, holder(1_000), context(), 1_000)
      entity = DiminishingReturns.reconcile(entity, [first], [second], 1_000)
      assert entity.internal.diminishing_returns.controlled_stun.reset_at == nil
      assert entity.internal.diminishing_returns.controlled_stun.applications == 2
    end
  end
end
