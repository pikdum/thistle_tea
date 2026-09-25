defmodule ThistleTea.Game.Entity.Logic.Companion do
  @moduledoc """
  Pure lifecycle transitions for a unit's canonical companion relationship.

  Unit summon and charm fields are derived client projections of this state.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetName
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid

  @summon_kinds [:hunter_pet, :guardian]
  @control_kinds [:enslaved, :charm, :possession]

  def activate(%Mob{} = entity, :guardian, %EntityRef{} = entity_ref) do
    put_relationship(entity, %Companion{kind: :guardian, status: {:active, entity_ref}, reaction_state: :aggressive})
  end

  def activate(
        %Character{
          internal: %Internal{companion: %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}} = companion}
        } = character,
        :possession,
        %EntityRef{guid: guid, spell_id: spell_id}
      )
      when kind in @summon_kinds do
    put_relationship(character, %{companion | possession_spell_id: spell_id})
  end

  def activate(%Character{} = character, kind, %EntityRef{} = entity_ref)
      when kind in @summon_kinds or kind in @control_kinds do
    {autocast, action_bar} = activation_controls(relationship(character), kind, entity_ref.entry)
    happiness = if kind == :hunter_pet and entry(character) == entity_ref.entry, do: relationship(character).happiness
    progress = if kind == :hunter_pet and entry(character) == entity_ref.entry, do: relationship(character).progress
    reaction = if entry(character) == entity_ref.entry, do: relationship(character).reaction_state, else: :defensive

    put_relationship(character, %Companion{
      kind: kind,
      status: {:active, entity_ref},
      pet_number: activation_number(character, kind, entity_ref),
      name: retained_name(character, kind, entity_ref.entry),
      health: retained_health(character, entity_ref.entry),
      autocast: autocast,
      action_bar: action_bar,
      happiness: happiness,
      progress: progress,
      reaction_state: reaction
    })
  end

  def remember_progress(%Character{} = character, guid, %PetProgress{} = progress) do
    if controls?(character, guid), do: capture_progress(character, progress), else: character
  end

  def remember_name(%Character{} = character, guid, %PetName{} = name) do
    case relationship(character) do
      %Companion{kind: :hunter_pet, status: {:active, %EntityRef{guid: ^guid}}} = companion ->
        put_relationship(character, %{companion | name: name})

      _ ->
        character
    end
  end

  def capture_progress(%Character{} = character, %PetProgress{} = progress) do
    case relationship(character) do
      %Companion{kind: :hunter_pet} = companion -> put_relationship(character, %{companion | progress: progress})
      _ -> character
    end
  end

  def capture_progress(%Character{} = character, _progress), do: character

  def set_automatic_restore(%Character{} = character, enabled?) when is_boolean(enabled?) do
    put_relationship(character, %{relationship(character) | restore_automatically?: enabled?})
  end

  def capture_health(%Character{} = character, health) when is_integer(health) and health >= 0 do
    case relationship(character) do
      %Companion{kind: :hunter_pet} = companion -> put_relationship(character, %{companion | health: health})
      _ -> character
    end
  end

  def remember_reaction(%Character{} = character, guid, reaction)
      when reaction in [:passive, :defensive, :aggressive] do
    if controls?(character, guid), do: capture_reaction(character, reaction), else: character
  end

  def capture_reaction(%Character{} = character, reaction) when reaction in [:passive, :defensive, :aggressive] do
    case relationship(character) do
      %Companion{kind: kind} = companion when kind in @summon_kinds ->
        put_relationship(character, %{companion | reaction_state: reaction})

      _ ->
        character
    end
  end

  def remember_happiness(%Character{} = character, guid, happiness) when is_integer(happiness) and happiness >= 0 do
    if controls?(character, guid), do: capture_happiness(character, happiness), else: character
  end

  def capture_happiness(%Character{} = character, happiness) when is_integer(happiness) and happiness >= 0 do
    case relationship(character) do
      %Companion{kind: :hunter_pet} = companion -> put_relationship(character, %{companion | happiness: happiness})
      _ -> character
    end
  end

  def remember_death(%Character{} = character, guid) do
    if controls?(character, guid), do: capture_death(character, true), else: character
  end

  def capture_death(%Character{} = character, dead?) when is_boolean(dead?) do
    case relationship(character) do
      %Companion{kind: :hunter_pet} = companion ->
        health = if dead?, do: 0, else: companion.health
        put_relationship(character, %{companion | dead?: dead?, health: health})

      _ ->
        character
    end
  end

  def suspend(%Character{internal: %Internal{companion: %Companion{} = companion}} = character) do
    case companion do
      %Companion{kind: kind, status: {:active, %EntityRef{} = entity_ref}} when kind in @summon_kinds ->
        put_relationship(character, %{
          companion
          | status: {:suspended, entity_ref.entry, entity_ref.spell_id},
            possession_spell_id: nil
        })

      %Companion{status: {:active, %EntityRef{}}} ->
        clear(character)

      %Companion{} ->
        project(character)
    end
  end

  def suspend(%Character{} = character), do: project(character)

  def removed(entity, reason \\ nil)
  def removed(%Mob{} = entity, _reason), do: clear(entity)

  def removed(%Character{} = character, reason) do
    case relationship(character) do
      %Companion{possession_spell_id: spell_id} = companion when is_integer(spell_id) and reason == :released ->
        put_relationship(character, %{companion | possession_spell_id: nil})

      %Companion{kind: :hunter_pet, status: {:active, %EntityRef{}}} when reason in [:owner_died, :process_down] ->
        suspend(character)

      %Companion{status: {:active, %EntityRef{}}} ->
        clear(character)

      %Companion{} ->
        project(character)
    end
  end

  def dismiss(entity, reason \\ nil)

  def dismiss(%Character{} = character, reason) do
    case relationship(character) do
      %Companion{kind: :hunter_pet, status: {:active, %EntityRef{} = entity_ref}} ->
        character = suspend(character)
        companion = %{relationship(character) | restore_automatically?: reason == :owner_died}
        character = put_relationship(character, companion)
        {character, [Effects.dismiss_pet(entity_ref.guid)]}

      %Companion{kind: kind, status: {:active, %EntityRef{} = entity_ref}} when kind in @summon_kinds ->
        character = if reason == :owner_died, do: suspend(character), else: clear(character)
        {character, [Effects.dismiss_pet(entity_ref.guid)]}

      %Companion{kind: kind, status: {:active, %EntityRef{} = entity_ref}} when kind in @control_kinds ->
        character = clear(character)
        effect = Effects.release_controlled(character.object.guid, entity_ref.guid, entity_ref.spell_id)
        {character, [effect]}

      %Companion{status: {:suspended, _entry, _spell_id}} ->
        character = if reason == :owner_died, do: character, else: clear(character)
        {project(character), []}

      _ ->
        {project(character), []}
    end
  end

  def dismiss(entity, _reason), do: {entity, []}

  def suspend_as(%Character{} = character, kind, entry, spell_id)
      when kind in @summon_kinds and is_integer(entry) and entry > 0 and is_integer(spell_id) do
    put_relationship(character, %Companion{kind: kind, status: {:suspended, entry, spell_id}})
  end

  def clear(%Character{} = character) do
    put_relationship(character, Companion.none())
  end

  def clear(%Mob{} = entity), do: put_relationship(entity, Companion.none())

  def restore(%Character{} = character, %Companion{status: {:suspended, _, _}} = companion) do
    put_relationship(character, companion)
  end

  def remember_controls(%Character{} = character, guid, %Pet{} = control) do
    if controls?(character, guid) do
      companion = %{relationship(character) | autocast: control.autocast, action_bar: control.action_bar}
      put_relationship(character, companion)
    else
      character
    end
  end

  def autocast(%Character{} = character) do
    case relationship(character) do
      %Companion{autocast: %MapSet{} = autocast} -> autocast
      %Companion{} -> MapSet.new()
    end
  end

  def relationship(%{internal: %Internal{companion: %Companion{} = companion}}), do: companion
  def relationship(%Character{}), do: Companion.none()
  def relationship(%Mob{}), do: Companion.none()

  def active_ref(%{internal: _internal} = character) do
    case relationship(character) do
      %Companion{status: {:active, %EntityRef{} = entity_ref}} -> entity_ref
      _ -> nil
    end
  end

  def active_guid(%{internal: _internal} = character) do
    case active_ref(character) do
      %EntityRef{guid: guid} -> guid
      _ -> nil
    end
  end

  def summon_guid(%Character{} = character) do
    case relationship(character) do
      %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}} when kind in @summon_kinds -> guid
      _ -> nil
    end
  end

  def control_guid(%Character{} = character) do
    case relationship(character) do
      %Companion{possession_spell_id: spell_id, status: {:active, %EntityRef{guid: guid}}}
      when is_integer(spell_id) ->
        guid

      %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}} when kind in @control_kinds ->
        guid

      _ ->
        nil
    end
  end

  def possession_guid(%Character{} = character) do
    case relationship(character) do
      %Companion{kind: :possession, status: {:active, %EntityRef{guid: guid}}} -> guid
      %Companion{possession_spell_id: spell, status: {:active, %EntityRef{guid: guid}}} when is_integer(spell) -> guid
      _ -> nil
    end
  end

  def creature_guid(%Character{} = character) do
    guid = active_guid(character)
    if Guid.entity_type(guid) == :mob, do: guid
  end

  def suspended(%Character{} = character) do
    case relationship(character) do
      %Companion{kind: kind, status: {:suspended, entry, spell_id}} -> {kind, entry, spell_id}
      _ -> nil
    end
  end

  def entry(%{internal: _internal} = character) do
    case relationship(character) do
      %Companion{status: {:active, %EntityRef{entry: entry}}} -> entry
      %Companion{status: {:suspended, entry, _spell_id}} -> entry
      _ -> nil
    end
  end

  def controls?(%Character{} = character, guid) when is_integer(guid), do: active_guid(character) == guid
  def controls?(%Character{}, _guid), do: false

  def project(%Character{unit: %Unit{} = unit} = character) do
    {summon, charm} =
      case relationship(character) do
        %Companion{kind: kind, possession_spell_id: spell_id, status: {:active, %EntityRef{guid: guid}}}
        when kind in @summon_kinds and is_integer(spell_id) ->
          {guid, guid}

        %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}} when kind in @summon_kinds ->
          {guid, 0}

        %Companion{kind: kind, status: {:active, %EntityRef{guid: guid}}} when kind in @control_kinds ->
          {0, guid}

        _ ->
          {0, 0}
      end

    %{character | unit: %{unit | summon: summon, charm: charm}}
  end

  def project(%Character{} = character), do: character

  def project(%Mob{unit: %Unit{} = unit} = entity), do: %{entity | unit: %{unit | summon: active_guid(entity) || 0}}

  defp put_relationship(%{internal: %Internal{} = internal} = character, %Companion{} = companion) do
    %{character | internal: %{internal | companion: companion}}
    |> project()
  end

  defp activation_controls(%Companion{kind: kind, status: status, autocast: autocast, action_bar: bar}, kind, entry) do
    case status do
      {:active, %EntityRef{entry: ^entry}} -> {autocast, bar}
      {:suspended, ^entry, _spell_id} -> {autocast, bar}
      _ -> {MapSet.new(), %{}}
    end
  end

  defp activation_controls(%Companion{}, _kind, _entry), do: {MapSet.new(), %{}}

  defp activation_number(character, :hunter_pet, entity_ref) do
    number = if entry(character) == entity_ref.entry, do: relationship(character).pet_number
    number || Guid.low_guid(entity_ref.guid)
  end

  defp activation_number(_character, _kind, _entity_ref), do: nil

  defp retained_health(character, entry) do
    if entry(character) == entry, do: relationship(character).health
  end

  defp retained_name(character, :hunter_pet, entry) do
    if entry(character) == entry and relationship(character).kind == :hunter_pet, do: relationship(character).name
  end

  defp retained_name(_character, _kind, _entry), do: nil
end
