defmodule ThistleTea.Game.Spell.Semantics.Rules do
  @moduledoc false

  @enforce_keys [
    :dummy,
    :apply_trigger_spell_id,
    :finish_trigger_spell_id,
    :judgement_damage?,
    :attack_power_damage?,
    :melee_spell_crit?
  ]
  defstruct [
    :dummy,
    :apply_trigger_spell_id,
    :finish_trigger_spell_id,
    :judgement_damage?,
    :attack_power_damage?,
    :melee_spell_crit?
  ]
end

defmodule ThistleTea.Game.Spell.Semantics.DamageHeal do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.Aura do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.Resource do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.Movement do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.SummonControl do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.Inventory do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.Script do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics.Unsupported do
  @moduledoc false
  @enforce_keys [:kind]
  defstruct [:kind]
end

defmodule ThistleTea.Game.Spell.Semantics do
  @moduledoc """
  Compiles DBC effect types and VMangos script metadata into typed gameplay
  rules at the spell-loader boundary.
  """

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Semantics.Aura
  alias ThistleTea.Game.Spell.Semantics.DamageHeal
  alias ThistleTea.Game.Spell.Semantics.Inventory
  alias ThistleTea.Game.Spell.Semantics.Movement
  alias ThistleTea.Game.Spell.Semantics.Resource
  alias ThistleTea.Game.Spell.Semantics.Rules
  alias ThistleTea.Game.Spell.Semantics.Script
  alias ThistleTea.Game.Spell.Semantics.SummonControl
  alias ThistleTea.Game.Spell.Semantics.Unsupported

  @damage_heal [
    :school_damage,
    :health_leech,
    :instakill,
    :heal,
    :heal_max_health,
    :weapon_damage,
    :weapon_damage_noschool,
    :normalized_weapon_damage,
    :weapon_percent_damage
  ]

  @aura [:apply_aura, :apply_area_aura, :persistent_area_aura, :dispel, :dispel_mechanic]
  @resource [:energize, :power_drain, :power_burn, :add_combo_points]
  @movement [:leap, :teleport_units, :charge, :add_farsight]

  @summon_control [
    :duel,
    :summon_pet,
    :revive_pet,
    :dismiss_pet,
    :summon_game_object,
    :summon_player,
    :summon_demon,
    :summon_possessed,
    :summon_totem,
    :tame_creature,
    :clear_threat,
    :attack_me,
    :add_extra_attacks,
    :modify_threat,
    :interrupt_cast,
    :resurrect,
    :resurrect_new,
    :trans_door
  ]

  @inventory [
    :create_item,
    :open_lock,
    :enchant_item,
    :enchant_item_temporary,
    :enchant_held_item,
    :feed_pet
  ]

  @script [:trigger_spell, :dummy, :script_effect, :learn_spell, :parry, :dual_wield, :proficiency]

  def compile(%Spell{} = spell) do
    effects = Enum.map(spell.effects, &compile_effect/1)

    %{
      spell
      | effects: effects,
        semantics: %Rules{
          dummy: Scripts.dummy_effect(spell),
          apply_trigger_spell_id: Scripts.apply_trigger(spell),
          finish_trigger_spell_id: Scripts.successful_finish_trigger(spell),
          judgement_damage?: Scripts.judgement_of_command_damage?(spell),
          attack_power_damage?: Scripts.ap_percent_damage?(spell),
          melee_spell_crit?: Scripts.uses_melee_spell_crit?(spell)
        }
    }
  end

  def compile_effect(%Effect{} = effect) do
    %{effect | semantic: effect_rule(effect)}
  end

  def effect_rule(%Effect{semantic: semantic}) when not is_nil(semantic), do: semantic
  def effect_rule(%Effect{type: type}) when type in @damage_heal, do: %DamageHeal{kind: type}
  def effect_rule(%Effect{type: type}) when type in @aura, do: %Aura{kind: type}
  def effect_rule(%Effect{type: type}) when type in @resource, do: %Resource{kind: type}
  def effect_rule(%Effect{type: type}) when type in @movement, do: %Movement{kind: type}
  def effect_rule(%Effect{type: type}) when type in @summon_control, do: %SummonControl{kind: type}
  def effect_rule(%Effect{type: type}) when type in @inventory, do: %Inventory{kind: type}
  def effect_rule(%Effect{type: type}) when type in @script, do: %Script{kind: type}
  def effect_rule(%Effect{type: type}), do: %Unsupported{kind: type}

  def rules(%Spell{semantics: %Rules{} = rules}), do: rules
  def rules(%Spell{} = spell), do: compile(spell).semantics
end
