defmodule ThistleTea.Game.Entity.Logic.PetNaming do
  @moduledoc "Pure hunter pet naming rules and the one-time rename permission projection."

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetName
  alias ThistleTea.Game.Entity.Logic.Core

  @rename_flag 0x10
  @abandon_flag 0x20
  @scripts [~r/\A\p{Latin}+\z/u, ~r/\A\p{Cyrillic}+\z/u, ~r/\A[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]+\z/u]

  def valid?(name) when is_binary(name) do
    String.valid?(name) and length(String.codepoints(name)) in 2..12 and
      Enum.any?(@scripts, &Regex.match?(&1, name))
  end

  def valid?(_name), do: false

  def initialize(%Mob{internal: %{pet: %Pet{kind: :hunter}}} = pet, nil) do
    %{pet | unit: %{pet.unit | flags: (pet.unit.flags || 0) ||| @rename_flag ||| @abandon_flag}}
  end

  def initialize(%Mob{internal: %{pet: %Pet{kind: :hunter}}} = pet, %PetName{} = name), do: project(pet, name)
  def initialize(%Mob{} = pet, _name), do: pet

  def rename(%Mob{internal: %{pet: %Pet{kind: :hunter, owner_guid: owner, broken?: false}}} = pet, owner, name, now)
      when is_integer(now) and now > 0 do
    cond do
      ((pet.unit.flags || 0) &&& @rename_flag) == 0 ->
        {:error, :unavailable}

      not valid?(name) ->
        {:error, :invalid_name}

      true ->
        identity = %PetName{name: name, timestamp: max(now, (pet.unit.pet_name_timestamp || 0) + 1)}
        {:ok, pet |> project(identity) |> Core.mark_broadcast_update(), identity}
    end
  end

  def rename(_pet, _owner, _name, _now), do: {:error, :unavailable}

  defp project(%Mob{} = pet, %PetName{name: name, timestamp: timestamp}) do
    flags = ((pet.unit.flags || 0) ||| @abandon_flag) &&& bnot(@rename_flag)
    unit = %{pet.unit | flags: flags, pet_name_timestamp: timestamp}
    %{pet | unit: unit, internal: %{pet.internal | name: name}}
  end
end
