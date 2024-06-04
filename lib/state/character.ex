defmodule ThistleTea.CharacterStorage do
  use Agent

  # %{ username => [char1, char2, char3, etc.] }

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_characters(username) do
    case Agent.get(__MODULE__, fn state -> Map.get(state, username) end) do
      nil -> []
      characters -> characters
    end
  end

  def add_character(username, character) do
    case get_characters(username) do
      nil ->
        Agent.update(__MODULE__, fn state -> Map.put(state, username, [character]) end)

      characters when length(characters) >= 10 ->
        {:error, "Character limit reached"}

      characters ->
        Agent.update(__MODULE__, fn state ->
          Map.put(state, username, [character | characters])
        end)
    end
  end
end
