defmodule ThistleTea.Game.Entity.Data.Item do
  @moduledoc """
  Item instance entity built from an `ItemTemplate`, optionally with a
  container component for bags. Items live in the `ItemStore`, never in
  visibility tracking.
  """
  import Bitwise, only: [bnot: 1, &&&: 2, <<<: 2, >>>: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Container
  alias ThistleTea.Game.Entity.Data.Component.Item, as: ItemComponent
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  defstruct object: %Object{},
            item: %ItemComponent{},
            container: nil,
            internal: %{template: nil}

  def build(%ItemTemplate{} = template, guid, opts \\ []) do
    owner = Keyword.get(opts, :owner, 0)
    stack_count = Keyword.get(opts, :stack_count, 1)

    %__MODULE__{
      object: %Object{
        guid: guid,
        entry: template.entry,
        scale_x: 1.0
      },
      item: %ItemComponent{
        owner: owner,
        contained: owner,
        stack_count: stack_count,
        duration: template.duration,
        spell_charges: pack_spell_charges(template),
        flags: template.flags,
        durability: template.max_durability,
        max_durability: template.max_durability
      },
      container: build_container(template),
      internal: %{template: template, enchantments: %{}}
    }
  end

  def template(%__MODULE__{internal: %{template: template}}), do: template

  def container?(%__MODULE__{container: %Container{}}), do: true
  def container?(%__MODULE__{}), do: false

  @temporary_enchantment_slot 1
  @enchantment_words_per_slot 3

  def temporary_enchantment_slot, do: @temporary_enchantment_slot

  def put_temporary_enchantment(%__MODULE__{} = item, enchantment_id, duration_ms, charges, expires_at, token) do
    enchantment = %{id: enchantment_id, expires_at: expires_at, charges: charges, token: token}
    enchantments = Map.put(Map.get(item.internal, :enchantments, %{}), @temporary_enchantment_slot, enchantment)

    item
    |> put_enchantment_word(@temporary_enchantment_slot, 0, enchantment_id)
    |> put_enchantment_word(@temporary_enchantment_slot, 1, duration_ms)
    |> put_enchantment_word(@temporary_enchantment_slot, 2, charges)
    |> put_internal_enchantments(enchantments)
  end

  def clear_temporary_enchantment(%__MODULE__{} = item) do
    enchantments = Map.delete(Map.get(item.internal, :enchantments, %{}), @temporary_enchantment_slot)

    item
    |> put_enchantment_word(@temporary_enchantment_slot, 0, 0)
    |> put_enchantment_word(@temporary_enchantment_slot, 1, 0)
    |> put_enchantment_word(@temporary_enchantment_slot, 2, 0)
    |> put_internal_enchantments(enchantments)
  end

  def temporary_enchantment(%__MODULE__{internal: internal}) do
    internal |> Map.get(:enchantments, %{}) |> Map.get(@temporary_enchantment_slot)
  end

  def refresh_temporary_enchantment(%__MODULE__{} = item, now) do
    case temporary_enchantment(item) do
      %{expires_at: expires_at} when expires_at <= now ->
        {clear_temporary_enchantment(item), nil}

      %{expires_at: expires_at} = enchantment ->
        remaining_ms = expires_at - now
        {put_enchantment_word(item, @temporary_enchantment_slot, 1, remaining_ms), enchantment}

      nil ->
        {item, nil}
    end
  end

  def visible_value(%__MODULE__{object: object} = item) do
    permanent = enchantment_word(item, 0, 0)
    temporary = enchantment_word(item, @temporary_enchantment_slot, 0)
    object.entry ||| permanent <<< 32 ||| temporary <<< 64
  end

  defp put_internal_enchantments(%__MODULE__{internal: internal} = item, enchantments) do
    %{item | internal: Map.put(internal, :enchantments, enchantments)}
  end

  defp put_enchantment_word(%__MODULE__{item: component} = item, slot, offset, value) do
    shift = (slot * @enchantment_words_per_slot + offset) * 32
    mask = 0xFFFFFFFF <<< shift
    packed = ((component.enchantment || 0) &&& bnot(mask)) ||| (value &&& 0xFFFFFFFF) <<< shift
    %{item | item: %{component | enchantment: packed}}
  end

  defp enchantment_word(%__MODULE__{item: component}, slot, offset) do
    shift = (slot * @enchantment_words_per_slot + offset) * 32
    (component.enchantment || 0) >>> shift &&& 0xFFFFFFFF
  end

  defp build_container(%ItemTemplate{container_slots: num_slots}) when is_integer(num_slots) and num_slots > 0 do
    Enum.reduce(1..36, %Container{num_slots: num_slots}, fn i, container ->
      Map.put(container, :"slot_#{i}", 0)
    end)
  end

  defp build_container(_template), do: nil

  defp pack_spell_charges(%ItemTemplate{} = template) do
    Enum.reduce(5..1//-1, 0, fn i, acc ->
      charges = Map.get(template, :"spellcharges_#{i}") || 0
      acc <<< 32 ||| (charges &&& 0xFFFFFFFF)
    end)
  end
end
