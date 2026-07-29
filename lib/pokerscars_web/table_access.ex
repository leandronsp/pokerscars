defmodule PokerscarsWeb.TableAccess do
  @moduledoc """
  Capability links for locked rooms: a signed token embedding the table code.
  Whoever holds the link gets in — that is the sharing model between friends.
  Typing the password mints the same token, so a reload keeps access.
  Revocation is closing the table; the salt never signs anything else.
  """

  @salt "table-access"
  @month_in_seconds 60 * 60 * 24 * 30

  @spec sign(String.t()) :: String.t()
  def sign(code), do: Phoenix.Token.sign(PokerscarsWeb.Endpoint, @salt, code)

  @spec valid?(String.t() | nil, String.t()) :: boolean()
  def valid?(nil, _code), do: false

  def valid?(key, code) do
    case Phoenix.Token.verify(PokerscarsWeb.Endpoint, @salt, key, max_age: @month_in_seconds) do
      {:ok, ^code} -> true
      _invalid -> false
    end
  end
end
