defmodule ThistleTea.Game.Entity.Data.Component.Internal.Pet do
  @moduledoc """
  Runtime ownership and command state shared by combat pets, guardians, and
  non-combat companions.
  """

  defstruct [
    :owner_guid,
    :profile,
    :kind,
    :food_mask,
    :control_spell_id,
    :next_happiness_at,
    :next_loyalty_at,
    :last_untrain_at,
    :original_faction_template,
    :original_npc_flags,
    :stay_position,
    :possession_original_kind,
    :possession_original_owner_guid,
    :possession_original_control_spell_id,
    :possession_original_unit_flags,
    :possession_original_command_state,
    :possession_original_reaction_state,
    loyalty_points: 1_000,
    training_points: 0,
    last_untrain_cost: 0,
    family_spells: MapSet.new(),
    owner_spell_modifiers: [],
    broken?: false,
    possessed?: false,
    action_bar: %{},
    command_state: :follow,
    reaction_state: :defensive,
    autocast: MapSet.new()
  ]
end
