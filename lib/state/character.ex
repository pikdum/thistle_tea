defmodule ThistleTea.CharacterStorage do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_characters(username) do
    case Agent.get(__MODULE__, fn state -> Map.get(state, username) end) do
      nil -> []
      characters -> characters
    end
  end

  def get_by_guid(username, guid) do
    case get_characters(username) do
      nil -> nil
      characters -> Enum.find(characters, &(&1.guid == guid))
    end
  end

  def add_character(username, character) do
    case get_characters(username) do
      nil ->
        Agent.update(__MODULE__, fn state -> Map.put(state, username, [character]) end)

      # CHAR_CREATE_ACCOUNT_LIMIT
      characters when length(characters) >= 10 ->
        {:error, 0x35}

      characters ->
        Agent.update(__MODULE__, fn state ->
          Map.put(state, username, characters ++ [character])
        end)
    end
  end
end
