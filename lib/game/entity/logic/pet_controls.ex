defmodule ThistleTea.Game.Entity.Logic.PetControls do
  @moduledoc "Validated pet action bars and autocast settings shared by commands and restoration."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell

  @command 0x07
  @reaction 0x06
  @enabled 0xC1
  @disabled 0x81
  @manual 0x01

  def update(
        %Mob{internal: %{pet: %Pet{owner_guid: owner, broken?: false, possessed?: false} = pet, spellbook: spells}} =
          mob,
        owner,
        request
      )
      when is_integer(owner) and owner > 0 and is_map(spells) do
    pet = normalize(pet, spells)

    case change(pet, spells, request) do
      {:ok, updated} -> {:ok, %{mob | internal: %{mob.internal | pet: updated}}}
      error -> error
    end
  end

  def update(%Mob{}, _owner, _request), do: {:error, :not_controlled}

  def normalize(%Pet{} = pet, spells) when is_map(spells) do
    autocast = MapSet.filter(pet.autocast, &autocastable?(Map.get(spells, &1)))
    pet = %{pet | autocast: autocast}
    defaults = default_bar(spells, pet)

    placed = MapSet.new(pet.action_bar, fn {_slot, {id, type}} -> if type in [@manual, @disabled, @enabled], do: id end)

    bar =
      Map.new(defaults, fn {slot, default} ->
        {id, type} = default
        default = if type not in [@command, @reaction] and MapSet.member?(placed, id), do: {0, @disabled}, else: default
        button = Map.get(pet.action_bar, slot, default)
        {slot, if(valid_button?(button, spells), do: button, else: {0, @disabled})}
      end)

    bar = if fixed_buttons(bar) == fixed_buttons(defaults), do: bar, else: defaults
    %{pet | action_bar: paint(bar, spells, autocast)}
  end

  def spell_state(%Spell{} = spell, autocast) do
    cond do
      not autocastable?(spell) -> @manual
      MapSet.member?(autocast, spell.id) -> @enabled
      true -> @disabled
    end
  end

  defp change(pet, spells, {:restore, bar, %MapSet{} = autocast}) when is_map(bar) do
    {:ok, normalize(%{pet | action_bar: bar, autocast: autocast}, spells)}
  end

  defp change(pet, spells, {:autocast, id, enabled?}) when is_boolean(enabled?) do
    if autocastable?(Map.get(spells, id)) do
      autocast = toggle(pet.autocast, id, enabled?)
      {:ok, %{pet | autocast: autocast, action_bar: paint(pet.action_bar, spells, autocast)}}
    else
      {:error, :invalid_spell}
    end
  end

  defp change(pet, spells, {:actions, actions}) when is_list(actions) and length(actions) in 1..2 do
    if valid_actions?(actions, spells) do
      bar =
        Enum.reduce(actions, pet.action_bar, fn action, bar ->
          Map.put(bar, action.position, {action.action, action.action_type})
        end)

      if fixed_buttons(bar) == fixed_buttons(pet.action_bar) do
        autocast = Enum.reduce(actions, pet.autocast, &apply_autocast/2)
        {:ok, %{pet | action_bar: paint(bar, spells, autocast), autocast: autocast}}
      else
        {:error, :invalid_action}
      end
    else
      {:error, :invalid_action}
    end
  end

  defp change(_pet, _spells, _request), do: {:error, :invalid_action}

  defp valid_actions?(actions, spells) do
    Enum.all?(actions, fn
      %{position: slot, action: id, action_type: type} when slot in 0..9 -> valid_button?({id, type}, spells)
      _ -> false
    end) and length(Enum.uniq_by(actions, & &1.position)) == length(actions)
  end

  defp valid_button?({id, type}, _spells) when type in [@command, @reaction] and id in 0..2, do: true
  defp valid_button?({0, type}, _spells) when type in [@manual, @disabled], do: true

  defp valid_button?({id, type}, spells) when type in [@manual, @disabled, @enabled] do
    case Map.get(spells, id) do
      %Spell{} = spell ->
        not Spell.attribute?(spell, :passive) and (type != @enabled or autocastable?(spell))

      _ ->
        false
    end
  end

  defp valid_button?(_button, _spells), do: false

  defp autocastable?(%Spell{} = spell) do
    not Spell.attribute?(spell, :passive) and not Spell.attribute?(spell, :no_autocast_ai)
  end

  defp autocastable?(_spell), do: false

  defp default_bar(spells, pet) do
    buttons =
      spells
      |> Map.values()
      |> Enum.reject(&Spell.attribute?(&1, :passive))
      |> Enum.sort_by(& &1.id)
      |> Enum.take(4)
      |> Enum.map(&{&1.id, spell_state(&1, pet.autocast)})

    actions =
      [{2, @command}, {1, @command}, {0, @command}] ++
        buttons ++
        List.duplicate({0, @disabled}, 4 - length(buttons)) ++ [{2, @reaction}, {1, @reaction}, {0, @reaction}]

    actions |> Enum.with_index() |> Map.new(fn {button, slot} -> {slot, button} end)
  end

  defp fixed_buttons(bar) do
    bar |> Map.values() |> Enum.filter(fn {_id, type} -> type in [@command, @reaction] end) |> Enum.sort()
  end

  defp paint(bar, spells, autocast) do
    Map.new(bar, fn
      {slot, {id, type}} when type in [@command, @reaction] -> {slot, {id, type}}
      {slot, {0, _type}} -> {slot, {0, @disabled}}
      {slot, {id, _type}} -> {slot, {id, spell_state(Map.fetch!(spells, id), autocast)}}
    end)
  end

  defp apply_autocast(%{action: id, action_type: @enabled}, autocast) when id > 0, do: toggle(autocast, id, true)
  defp apply_autocast(%{action: id, action_type: @disabled}, autocast) when id > 0, do: toggle(autocast, id, false)
  defp apply_autocast(_action, autocast), do: autocast

  defp toggle(autocast, id, true), do: MapSet.put(autocast, id)
  defp toggle(autocast, id, false), do: MapSet.delete(autocast, id)
end
