defmodule ThistleTea.Game.Entity.Logic.Aura.ReactiveArmor do
  @moduledoc "Selects school-specific defensive procs from the incoming spell and current armor auras."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @obsidian_armor 27_539
  @adaptive_warding 28_764
  @responses %{
    @obsidian_armor => %{1 => 27_536, 2 => 27_533, 3 => 27_538, 4 => 27_534, 5 => 27_535, 6 => 27_540},
    @adaptive_warding => %{2 => 28_765, 3 => 28_768, 4 => 28_766, 5 => 28_769, 6 => 28_770}
  }

  def events(holders, %Holder{spell: %Spell{id: id}} = holder, owner_guid, %{spell: %Spell{} = incoming})
      when is_map_key(@responses, id) do
    with true <- armor_active?(id, holders),
         spell_id when is_integer(spell_id) <- Map.get(@responses[id], Spell.school_index(incoming)) do
      [
        Effects.trigger_spell(owner_guid, holder.caster_level || 1, owner_guid, spell_id,
          cast_item_guid: holder.cast_item_guid,
          triggered_by_spell_id: id,
          requires_living_target?: true
        )
      ]
    else
      _ineligible -> []
    end
  end

  def events(_holders, _holder, _owner_guid, _context), do: []

  defp armor_active?(@adaptive_warding, holders) do
    Enum.any?(holders, fn %Holder{spell: spell} = holder ->
      Spell.family_flag?(spell, 3, 0x10000000) and Holder.has_aura_type?(holder, :mod_mana_regen_interrupt)
    end)
  end

  defp armor_active?(@obsidian_armor, _holders), do: true
end
