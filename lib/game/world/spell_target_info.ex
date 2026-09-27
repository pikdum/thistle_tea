defmodule ThistleTea.Game.World.SpellTargetInfo do
  @moduledoc "Builds the live unit facts consumed by pure spell admission checks."

  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
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
    :aura_sources,
    :dispel_options,
    :friendly_mechanic_immunities,
    :area
  ]

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
          position: World.position(guid),
          orientation: Map.get(metadata, :orientation),
          aura_sources: Map.get(metadata, :aura_sources, MapSet.new()),
          dispel_options: Map.get(metadata, :dispel_options, MapSet.new()),
          friendly_mechanic_immunities: Map.get(metadata, :friendly_mechanic_immunities, MapSet.new()),
          area: Map.get(metadata, :area),
          los?: World.line_of_sight?(caster, guid)
        }
    end
  end
end
