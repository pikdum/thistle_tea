defmodule ThistleTea.Game.Entity.Logic.Companion do
  @moduledoc """
  Pure lifecycle transitions for a player's canonical companion relationship.

  Unit summon and charm fields are derived client projections of this state.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid

  @summon_kinds [:hunter_pet, :guardian]
  @control_kinds [:enslaved, :charm, :possession]
  @act_enabled 0xC1
  @act_disabled 0x81

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
    autocast = activation_autocast(relationship(character), kind, entity_ref.entry)
    happiness = if kind == :hunter_pet and entry(character) == entity_ref.entry, do: relationship(character).happiness
    progress = if kind == :hunter_pet and entry(character) == entity_ref.entry, do: relationship(character).progress
    reaction = if entry(character) == entity_ref.entry, do: relationship(character).reaction_state, else: :defensive

    put_relationship(character, %Companion{
      kind: kind,
      status: {:active, entity_ref},
      pet_number: activation_number(character, kind, entity_ref),
      health: retained_health(character, entity_ref.entry),
      autocast: autocast,
      happiness: happiness,
      progress: progress,
      reaction_state: reaction
    })
  end

  def remember_progress(%Character{} = character, guid, %PetProgress{} = progress) do
    if controls?(character, guid), do: capture_progress(character, progress), else: character
  end

  def capture_progress(%Character{} = character, %PetProgress{} = progress) do
    case relationship(character) do
      %Companion{kind: :hunter_pet} = companion -> put_relationship(character, %{companion | progress: progress})
      _ -> character
    end
  end

  def capture_progress(%Character{} = character, _progress), do: character

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

  def removed(%Character{} = character, reason \\ nil) do
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

  def restore(%Character{} = character, %Companion{status: {:suspended, _, _}} = companion) do
    put_relationship(character, companion)
  end

  def set_autocast(%Character{} = character, actions) when is_list(actions) do
    case relationship(character) do
      %Companion{kind: kind, status: {:active, %EntityRef{}}, autocast: autocast} = companion
      when kind in @summon_kinds ->
        companion = %{companion | autocast: Enum.reduce(actions, autocast, &update_autocast/2)}
        put_relationship(character, companion)

      %Companion{} ->
        character
    end
  end

  def set_autocast(%Character{} = character, _actions), do: character

  def autocast(%Character{} = character) do
    case relationship(character) do
      %Companion{autocast: %MapSet{} = autocast} -> autocast
      %Companion{} -> MapSet.new()
    end
  end

  def relationship(%Character{internal: %Internal{companion: %Companion{} = companion}}), do: companion
  def relationship(%Character{}), do: Companion.none()

  def active_ref(%Character{} = character) do
    case relationship(character) do
      %Companion{status: {:active, %EntityRef{} = entity_ref}} -> entity_ref
      _ -> nil
    end
  end

  def active_guid(%Character{} = character) do
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

  def suspended(%Character{} = character) do
    case relationship(character) do
      %Companion{kind: kind, status: {:suspended, entry, spell_id}} -> {kind, entry, spell_id}
      _ -> nil
    end
  end

  def entry(%Character{} = character) do
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

  defp put_relationship(%Character{internal: %Internal{} = internal} = character, %Companion{} = companion) do
    %{character | internal: %{internal | companion: companion}}
    |> project()
  end

  defp activation_autocast(%Companion{kind: kind, status: status, autocast: %MapSet{} = autocast}, kind, entry) do
    case status do
      {:active, %EntityRef{entry: ^entry}} -> autocast
      {:suspended, ^entry, _spell_id} -> autocast
      _ -> MapSet.new()
    end
  end

  defp activation_autocast(%Companion{}, _kind, _entry), do: MapSet.new()

  defp activation_number(character, :hunter_pet, entity_ref) do
    number = if entry(character) == entity_ref.entry, do: relationship(character).pet_number
    number || Guid.low_guid(entity_ref.guid)
  end

  defp activation_number(_character, _kind, _entity_ref), do: nil

  defp retained_health(character, entry) do
    if entry(character) == entry, do: relationship(character).health
  end

  defp update_autocast(%{action: spell_id, action_type: @act_enabled}, autocast)
       when is_integer(spell_id) and spell_id > 0, do: MapSet.put(autocast, spell_id)

  defp update_autocast(%{action: spell_id, action_type: @act_disabled}, autocast)
       when is_integer(spell_id) and spell_id > 0, do: MapSet.delete(autocast, spell_id)

  defp update_autocast(_action, autocast), do: autocast
end
