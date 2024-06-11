defmodule ThistleTea.Character do
  use Memento.Table,
    attributes: [
      :id,
      :account_id,
      :name,
      :race,
      :class,
      :gender,
      :skin,
      :face,
      :hair_style,
      :hair_color,
      :facial_hair,
      :level,
      # TODO: maybe orientation should be elsewhere?
      :area,
      :map,
      :x,
      :y,
      :z,
      :orientation,
      # TODO: is this needed?
      :outfit_id
    ],
    index: [:account_id, :name],
    type: :ordered_set,
    autoincrement: true

  def create(character) do
    with {:exists, false} <- {:exists, character_exists?(character.name)},
         {:limit, false} <- {:limit, at_character_limit?(character.account_id)},
         {:ok, character} <- create_character(character) do
      {:ok, character}
    else
      {:exists, true} -> {:error, :character_exists}
      {:limit, true} -> {:error, :character_limit}
      {:error, reason} -> {:error, reason}
    end
  end

  def character_exists?(name) do
    case get_character(name) do
      {:error, _} -> false
      _ -> true
    end
  end

  def at_character_limit?(account_id) do
    case get_characters!(account_id) do
      characters when length(characters) >= 10 -> true
      _ -> false
    end
  end

  def get_character(account_id, character_id) do
    case Memento.transaction!(fn ->
           Memento.Query.select(
             ThistleTea.Character,
             [{:==, :account_id, account_id}, {:==, :id, character_id}]
           )
         end) do
      [] -> {:error, :character_not_found}
      [character] -> {:ok, character}
    end
  end

  def get_character(name) do
    case Memento.transaction!(fn ->
           Memento.Query.select(ThistleTea.Character, {:==, :name, name})
         end) do
      [] -> {:error, :character_not_found}
      [character] -> {:ok, character}
    end
  end

  def get_characters!(account_id) do
    Memento.transaction!(fn ->
      Memento.Query.select(ThistleTea.Character, {:==, :account_id, account_id})
    end)
  end

  def update_position!(character, position) do
    character = Map.merge(character, position)

    Memento.transaction!(fn ->
      Memento.Query.write(character)
    end)
  end

  defp create_character(character) do
    character =
      Memento.transaction!(fn ->
        Memento.Query.write(character)
      end)

    {:ok, character}
  end
end
