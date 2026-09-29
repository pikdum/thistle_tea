defmodule ThistleTea.Game.World.Spell.SpellTargetInfo do
  @moduledoc "Builds the live unit facts consumed by pure spell admission checks."

  alias ThistleTea.Game.Core.Battleground.Insignia
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.InsigniaTarget
  alias ThistleTea.Game.World.Spell.ResurrectionTarget
  alias ThistleTea.Game.World.Visibility

  @target_fields [
    :alive?,
    :feigning_death?,
    :faction_template,
    :unit_flags,
    :charmed_by,
    :health_pct,
    :power_type,
    :shapeshift_form,
    :level,
    :tameable?,
    :pickpocket_id,
    :skinning_id,
    :skinned?,
    :body_loot?,
    :owner_guid,
    :orientation,
    :creature_type,
    :combat_reach,
    :lateral_speed,
    :aura_sources,
    :dispel_options,
    :friendly_mechanic_immunities,
    :invulnerability_interruptible?,
    :area
  ]

  def resolve(%{object: %{guid: caster_guid}} = character, %Spell{} = spell, %Target{} = targets) do
    unit_guid = Target.unit_guid(targets)
    explicit_guid = nonself_guid(unit_guid, caster_guid)
    pet_guid = implicit_pet_guid(character, spell)

    fallback_guid =
      if Spell.requires_hostile_target?(spell) do
        nonself_guid(selected_target(character), caster_guid)
      end

    cond do
      Insignia.spell?(spell) -> InsigniaTarget.info(character, targets)
      Spell.resurrect_spell?(spell) -> ResurrectionTarget.info(character, targets, spell)
      is_integer(pet_guid) -> build(character, pet_guid, spell)
      is_integer(explicit_guid) -> build(character, explicit_guid, spell)
      is_integer(fallback_guid) -> build(character, fallback_guid, spell)
      unit_guid == caster_guid -> :self
      true -> nil
    end
  end

  defp implicit_pet_guid(%Character{} = character, %Spell{effects: effects}) do
    pet_guid =
      if Enum.any?(effects, &(&1.type == :feed_pet)) do
        Companion.summon_guid(character)
      else
        Character.controlled_guid(character)
      end

    if Enum.any?(effects, &(&1.type == :feed_pet or &1.implicit_target_a == :pet or &1.implicit_target_b == :pet)),
      do: positive_guid(pet_guid)
  end

  defp implicit_pet_guid(_character, _spell), do: nil

  defp positive_guid(guid) when is_integer(guid) and guid > 0, do: guid
  defp positive_guid(_guid), do: nil

  defp nonself_guid(guid, caster_guid) when is_integer(guid) and guid > 0 and guid != caster_guid, do: guid
  defp nonself_guid(_guid, _caster_guid), do: nil

  defp selected_target(%{unit: %Unit{target: target}}), do: target
  defp selected_target(_character), do: nil

  def build(caster, guid, %Spell{} = spell) do
    case Metadata.query(guid, @target_fields) do
      nil ->
        :unknown

      metadata ->
        metadata = Map.put(metadata, :guid, guid)

        %{
          guid: guid,
          visible?: Visibility.can_see?(%{guid: caster.object.guid, character: caster}, guid),
          unit_flags: Map.get(metadata, :unit_flags, 0),
          charmed_by: Map.get(metadata, :charmed_by),
          feigning_death?: Map.get(metadata, :feigning_death?, false),
          alive?: Map.get(metadata, :alive?, true),
          hostile?: Hostility.hostile?(caster, metadata),
          friendly?: Hostility.friendly?(caster, metadata),
          attackable?:
            Hostility.valid_attack_target?(caster, guid, allow_dead?: Spell.attribute?(spell, :allow_dead_target)),
          helpful?: Hostility.can_assist?(caster, guid),
          health_pct: Map.get(metadata, :health_pct),
          power_type: Map.get(metadata, :power_type),
          shapeshift_form: Map.get(metadata, :shapeshift_form, 0),
          level: Map.get(metadata, :level),
          tameable?: Map.get(metadata, :tameable?, false),
          pickpocket_id: Map.get(metadata, :pickpocket_id),
          skinning_id: Map.get(metadata, :skinning_id),
          skinned?: Map.get(metadata, :skinned?, false),
          body_loot?: Map.get(metadata, :body_loot?, true),
          owner_guid: Map.get(metadata, :owner_guid),
          creature_type: Map.get(metadata, :creature_type),
          combat_reach: Map.get(metadata, :combat_reach),
          lateral_speed: Map.get(metadata, :lateral_speed, 0.0),
          position: World.position(guid),
          orientation: Map.get(metadata, :orientation),
          aura_sources: Map.get(metadata, :aura_sources, MapSet.new()),
          dispel_options: Map.get(metadata, :dispel_options, MapSet.new()),
          friendly_mechanic_immunities: Map.get(metadata, :friendly_mechanic_immunities, MapSet.new()),
          invulnerability_interruptible?: Map.get(metadata, :invulnerability_interruptible?, false),
          area: Map.get(metadata, :area),
          los?: World.line_of_sight?(caster, guid)
        }
    end
  end
end
