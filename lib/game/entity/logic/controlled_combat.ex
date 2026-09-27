defmodule ThistleTea.Game.Entity.Logic.ControlledCombat do
  @moduledoc """
  Propagates a controlled creature's hostile contact to its current player owner.

  Contact starts the owner's combat window. A summoned companion's incoming
  threat can retain that combat independently of the owner's own references.
  Ownership and hostile references are validated against an immutable snapshot.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.CombatReferences
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.FeignDeath
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Guid

  def contact(%Mob{object: %{guid: guid}, unit: %{health: health}} = entity, opponent, now, role)
      when is_number(health) and health > 0 and is_integer(opponent) and opponent > 0 and opponent != guid and
             is_integer(now) and role in [:attack, :attacked] do
    owner = owner_guid(entity)

    if propagate?(entity, owner, opponent) do
      Effects.enqueue(entity, %Effects.ControlledCombatContact{
        target_guid: owner,
        controlled_guid: guid,
        opponent_guid: opponent,
        now: now,
        role: role
      })
    else
      entity
    end
  end

  def contact(entity, _opponent, _now, _role), do: entity

  defp propagate?(entity, owner, opponent) do
    is_integer(owner) and owner > 0 and Guid.entity_type(owner) == :player and
      Guid.entity_type(opponent) in [:player, :mob, :pet] and not CreatureFlags.no_owner_threat?(entity)
  end

  def receive(
        %Character{object: %{guid: owner}, unit: %{health: health}} = character,
        %Effects.ControlledCombatContact{target_guid: owner, controlled_guid: guid} = contact,
        %Context{perception: perception}
      )
      when health > 0 do
    if controls?(character, guid) and owned_here?(character, guid, perception) do
      apply_contact(character, contact, perception)
    else
      character
    end
  end

  def receive(character, _contact, %Context{}), do: character

  def holds_combat?(%Character{} = character, %Context{perception: perception}) do
    guid = Companion.summon_guid(character)

    if not FeignDeath.successful?(character) and owned_here?(character, guid, perception) do
      case Perception.metadata(perception, guid) do
        %{alive?: true, threat_refs: %MapSet{} = refs} ->
          refs |> CombatReferences.prune(character.internal.world, perception) |> MapSet.size() |> Kernel.>(0)

        _ ->
          false
      end
    else
      false
    end
  end

  def projection(%Mob{} = entity) do
    %{
      threat_refs: entity.internal.threat_refs || MapSet.new(),
      no_owner_threat?: CreatureFlags.no_owner_threat?(entity)
    }
  end

  defp controls?(%Character{internal: internal} = character, guid) do
    Companion.controls?(character, guid) or Map.has_key?(internal.guardians, guid) or
      guid in Map.values(internal.totem_guids)
  end

  defp owned_here?(%Character{object: %{guid: owner}, internal: %{world: world}}, guid, perception) do
    case {Perception.position(perception, guid), Perception.metadata(perception, guid)} do
      {{^world, _, _, _}, %{owner_guid: ^owner} = metadata} -> metadata[:no_owner_threat?] != true
      _ -> false
    end
  end

  defp apply_contact(character, %Effects.ControlledCombatContact{} = contact, perception) do
    opponent = Perception.actor(perception, contact.opponent_guid)
    targetable? = not FeignDeath.successful?(character) and Hostility.targetable_by?(opponent, character)

    case contact.role do
      :attacked when targetable? ->
        PlayerCombat.mark_attacked(character, contact.now, nil, contact.opponent_guid)

      :attack ->
        character = PlayerCombat.hold_combat(character, contact.now, 5_000, contact.opponent_guid)

        if targetable? do
          Effects.enqueue(character, %Effects.AddThreat{
            source_guid: character.object.guid,
            target_guid: contact.opponent_guid,
            amount: 0
          })
        else
          character
        end

      _ ->
        character
    end
  end

  defp owner_guid(%Mob{internal: %{pet: %Pet{owner_guid: owner}}}), do: owner
  defp owner_guid(%Mob{internal: %{totem: %Totem{owner_guid: owner}}}), do: owner
  defp owner_guid(%Mob{}), do: nil
end
