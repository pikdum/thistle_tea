defmodule ThistleTea.Game.World.Loader.Character do
  @moduledoc """
  Builds a fresh character entity from the Mangos player-create-info tables
  and DBC race data: starting components, position, spells, and action
  buttons for the chosen race/class.
  """
  import Bitwise, only: [|||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader

  @unit_flag_player_controlled 0x00000008
  @unit_flag_use_swim_animation 0x00008000

  def build(params, account_id) do
    info = Mangos.PlayerCreateInfo.get(params.race, params.class)
    spells = Mangos.PlayerCreateInfoSpell.get_all(params.race, params.class)
    action_buttons = Mangos.PlayerCreateInfoAction.get_all(params.race, params.class)
    starting_items = Mangos.PlayerCreateInfoItem.get_all(params.race, params.class)
    chr_race = DBC.get_by(ChrRaces, id: params.race)
    stats = Stats.get!(params.race, params.class, 1)

    unit_display_id =
      case(params.gender) do
        0 -> chr_race.male_display
        1 -> chr_race.female_display
      end

    %Character{
      account_id: account_id,
      object: %Object{
        scale_x: 1.0
      },
      unit: %Unit{
        health: stats.max_health,
        power1: stats.max_mana,
        power2: 0,
        power3: 0,
        power4: initial_energy(params.class),
        power5: 0,
        max_health: stats.max_health,
        max_power1: stats.max_mana,
        max_power2: max_rage(params.class),
        max_power3: 0,
        max_power4: initial_energy(params.class),
        max_power5: 0,
        level: stats.level,
        faction_template: chr_race.faction,
        race: params.race,
        class: params.class,
        gender: params.gender,
        power_type: get_power(params.class),
        base_attack_time: 2000,
        offhand_attack_time: 2000,
        min_offhand_damage: 0.0,
        max_offhand_damage: 0.0,
        bounding_radius: Unit.default_bounding_radius(),
        combat_reach: Unit.default_combat_reach(),
        display_id: unit_display_id,
        native_display_id: unit_display_id,
        min_damage: 10,
        max_damage: 50,
        mod_cast_speed: 1.0,
        strength: stats.strength,
        agility: stats.agility,
        stamina: stats.stamina,
        intellect: stats.intellect,
        spirit: stats.spirit,
        base_strength: stats.strength,
        base_agility: stats.agility,
        base_stamina: stats.stamina,
        base_intellect: stats.intellect,
        base_spirit: stats.spirit,
        base_mana: stats.base_mana,
        base_health: stats.base_health,
        sheath_state: 0,
        flags: @unit_flag_player_controlled ||| @unit_flag_use_swim_animation,
        auras: []
      },
      player: %Player{
        flags: 0,
        mod_damage_done_pct_physical: 1.0,
        mod_damage_done_pct_holy: 1.0,
        mod_damage_done_pct_fire: 1.0,
        mod_damage_done_pct_nature: 1.0,
        mod_damage_done_pct_frost: 1.0,
        mod_damage_done_pct_shadow: 1.0,
        mod_damage_done_pct_arcane: 1.0,
        skin: params.skin_color,
        face: params.face,
        hair_style: params.hair_style,
        hair_color: params.hair_color,
        facial_hair: params.facial_hair,
        rest_state: 2,
        xp: 0,
        next_level_xp: stats.next_level_xp,
        rest_state_experience: 0,
        coinage: 0,
        skills: SkillLoader.initial_skills(spells, params.race, params.class, stats.level)
      },
      movement_block:
        Map.merge(
          %MovementBlock{
            movement_flags: 0,
            position: {info.position_x, info.position_y, info.position_z, info.orientation},
            fall_time: 0,
            turn_rate: 3.1415,
            timestamp: 0
          },
          MovementBlock.player_speeds()
        ),
      internal: %Internal{
        name: params.name,
        area: info.zone,
        map: info.map,
        home_bind: {info.map, info.position_x, info.position_y, info.position_z},
        spells: spells,
        starting_items: starting_items,
        action_buttons: action_buttons
      }
    }
  end

  defp get_power(1), do: 1
  defp get_power(4), do: 3
  defp get_power(class) when class in [2, 3, 5, 7, 8, 9, 11], do: 0

  defp max_rage(1), do: 1000
  defp max_rage(_class), do: 0

  defp initial_energy(4), do: 100
  defp initial_energy(_class), do: 0
end
