defmodule ThistleTea.DBC.MailTemplate do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "MailTemplate" do
    field(:body, :string, source: :body_en_gb)
  end
end
