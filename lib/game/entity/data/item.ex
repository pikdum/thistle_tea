defmodule ThistleTea.Game.Entity.Data.Item do
  @moduledoc """
  Item instance entity built from an `ItemTemplate`, optionally with a
  container component for bags. Items live in the `ItemStore`, never in
  visibility tracking.
  """
  import Bitwise, only: [&&&: 2, <<<: 2, |||: 2]

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
      internal: %{template: template}
    }
  end

  def template(%__MODULE__{internal: %{template: template}}), do: template

  def container?(%__MODULE__{container: %Container{}}), do: true
  def container?(%__MODULE__{}), do: false

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
