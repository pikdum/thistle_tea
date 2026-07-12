defmodule ThistleTea.Game.Entity.Logic.Warlock do
  @moduledoc """
  Pure Warlock-specific mechanics whose semantics are not fully expressed by
  generic DBC effects.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @life_tap_ids [1454, 1455, 1456, 11_687, 11_688, 11_689]
  @conflagrate_ids [17_962, 18_930, 18_931, 18_932]
  @healthstone_items %{
    6201 => {5512, 19_004, 19_005},
    6202 => {5511, 19_006, 19_007},
    5699 => {5509, 19_008, 19_009},
    11_729 => {5510, 19_010, 19_011},
    11_730 => {9421, 19_012, 19_013}
  }
  @sacrifice_buffs %{416 => 18_789, 1860 => 18_790, 1863 => 18_791, 417 => 18_792}

  def life_tap?(%Spell{id: id}), do: id in @life_tap_ids
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

  def conflagrate?(%Spell{id: id}), do: id in @conflagrate_ids
  def conflagrate?(_spell), do: false

  def consume_immolate(state, caster_guid, now) do
    spell_ids =
      state.unit.auras
      |> Enum.find_value([], fn
        %Holder{caster_guid: ^caster_guid, spell: %Spell{id: id, name: "Immolate"}} -> [id]
        _ -> nil
      end)

    Aura.remove_spells(state, spell_ids, now)
  end

  def has_immolate_from?(%{unit: %{auras: holders}}, caster_guid) when is_list(holders) do
    Enum.any?(holders, fn
      %Holder{caster_guid: ^caster_guid, spell: %Spell{name: "Immolate"}} -> true
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
