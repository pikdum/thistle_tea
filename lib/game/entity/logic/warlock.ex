defmodule ThistleTea.Game.Entity.Logic.Warlock do
  @moduledoc """
  Pure Warlock-specific mechanics whose semantics are not fully expressed by
  generic DBC effects.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @spell_family 5
  @immolate_family_mask 0x00000004
  @agony_family_mask 0x00000400
  @healthstone_items %{
    6201 => {5512, 19_004, 19_005},
    6202 => {5511, 19_006, 19_007},
    5699 => {5509, 19_008, 19_009},
    11_729 => {5510, 19_010, 19_011},
    11_730 => {9421, 19_012, 19_013}
  }
  @sacrifice_buffs %{416 => 18_789, 1860 => 18_790, 1863 => 18_791, 417 => 18_792}
  @devour_magic_heals %{19_505 => 19_658, 19_731 => 19_732, 19_734 => 19_733, 19_736 => 19_735}

  def life_tap?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_warlock_life_tap")
  def life_tap?(_spell), do: false

  def life_tap_cost(%Spell{} = spell) do
    case Enum.find(spell.effects, &(&1.type == :dummy)) do
      %Effect{} = effect -> max(Effect.damage_roll(effect), 0)
      _ -> 0
    end
  end

  def life_tap(state, %CastContext{} = context, %Spell{}, %Effect{} = effect, now) do
    damage = max(Effect.damage_roll(effect) + shadow_bonus(context), 0)

    if (state.unit.health || 0) > damage do
      state = Core.take_damage(state, damage, now, school: :shadow, source: state.object.guid)
      {Resources.gain_power(state, 0, damage), []}
    else
      {state, []}
    end
  end

  def conflagrate?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_warlock_conflagrate")
  def conflagrate?(_spell), do: false

  def immolate?(%Spell{} = spell), do: Spell.family_flag?(spell, @spell_family, @immolate_family_mask)
  def immolate?(_spell), do: false

  def curse_of_agony?(%Spell{} = spell), do: Spell.family_flag?(spell, @spell_family, @agony_family_mask)
  def curse_of_agony?(_spell), do: false

  def demonic_sacrifice?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_warlock_demonic_sacrifice")
  def demonic_sacrifice?(_spell), do: false

  def devour_magic_heal(%Spell{id: id} = spell) do
    if Spell.vmangos_script?(spell, "spell_warlock_devour_magic"), do: Map.get(@devour_magic_heals, id)
  end

  def devour_magic_heal(_spell), do: nil

  def ritual_of_summoning?(%Spell{} = spell) do
    Spell.vmangos_script?(spell, "spell_warlock_ritual_of_summoning")
  end

  def ritual_of_summoning?(_spell), do: false

  def allow_periodic_trigger?(%{object: %{guid: target_guid}, unit: %{auras: holders}}, %Holder{
        spell: %Spell{} = spell,
        caster_guid: caster_guid
      })
      when is_list(holders) do
    if Spell.vmangos_script?(spell, "spell_warlock_curse_of_idiocy") do
      caster_guid != target_guid and not idiocy_stat_cap_reached?(holders, spell.id)
    else
      true
    end
  end

  def allow_periodic_trigger?(_entity, _holder), do: true

  def validate_ritual(%Spell{} = spell, context) do
    if ritual_of_summoning?(spell) do
      validate_ritual_context(context)
    else
      :ok
    end
  end

  defp validate_ritual_context(%{
         target_player?: true,
         target_online?: true,
         self?: false,
         same_group?: true,
         target_in_combat?: false,
         caster_dungeon?: true,
         same_world?: false
       }), do: {:error, :target_not_in_instance}

  defp validate_ritual_context(%{
         target_player?: true,
         target_online?: true,
         self?: false,
         same_group?: true,
         target_in_combat?: false,
         caster_battleground?: true
       }), do: {:error, :not_here}

  defp validate_ritual_context(%{
         target_player?: true,
         target_online?: true,
         self?: false,
         same_group?: true,
         target_in_combat?: false
       }), do: :ok

  defp validate_ritual_context(%{target_in_combat?: true}), do: {:error, :target_in_combat}
  defp validate_ritual_context(_invalid), do: {:error, :bad_targets}

  defp idiocy_stat_cap_reached?(holders, spell_id) do
    losses =
      Enum.reduce(holders, %{3 => 0, 4 => 0}, fn
        %Holder{spell: %Spell{id: ^spell_id}, stacks: stacks, auras: auras}, acc ->
          multiplier = max(stacks || 1, 1)

          Enum.reduce(auras, acc, fn
            %AuraData{type: :mod_stat, misc_value: stat, amount: amount}, inner when stat in [3, 4] ->
              Map.update!(inner, stat, &(&1 + amount * multiplier))

            _aura, inner ->
              inner
          end)

        _holder, acc ->
          acc
      end)

    losses[3] <= -90 and losses[4] <= -90
  end

  def immolate_source?(sources, caster_guid) do
    Enum.any?(sources, fn
      {_id, @spell_family, flags_0, _flags_1, ^caster_guid} when is_integer(flags_0) ->
        (flags_0 &&& @immolate_family_mask) != 0

      _source ->
        false
    end)
  end

  def consume_immolate(state, caster_guid, now) do
    spell_ids =
      state.unit.auras
      |> Enum.find_value([], fn
        %Holder{caster_guid: ^caster_guid, spell: %Spell{id: id} = spell} ->
          if immolate?(spell), do: [id]

        _ ->
          nil
      end)

    Aura.remove_spells(state, spell_ids, now)
  end

  def has_immolate_from?(%{unit: %{auras: holders}}, caster_guid) when is_list(holders) do
    Enum.any?(holders, fn
      %Holder{caster_guid: ^caster_guid, spell: %Spell{} = spell} -> immolate?(spell)
      _ -> false
    end)
  end

  def has_immolate_from?(_state, _caster_guid), do: false

  def healthstone_item(%{unit: unit}, %Spell{id: spell_id}) do
    rank =
      cond do
        Aura.has_spell?(%{unit: unit}, 18_693) -> 2
        Aura.has_spell?(%{unit: unit}, 18_692) -> 1
        true -> 0
      end

    case Map.get(@healthstone_items, spell_id) do
      items when is_tuple(items) -> elem(items, rank)
      _ -> nil
    end
  end

  def sacrifice_event(%{object: %{entry: entry}}, %CastContext{} = context) do
    case Map.get(@sacrifice_buffs, entry) do
      spell_id when is_integer(spell_id) ->
        Event.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, spell_id)

      _ ->
        nil
    end
  end

  defp shadow_bonus(%CastContext{spell_damage_bonus: bonuses}) when is_map(bonuses) do
    case Map.get(bonuses, :shadow, 0) do
      bonus when is_number(bonus) -> trunc(bonus)
      _ -> 0
    end
  end

  defp shadow_bonus(_context), do: 0
end
