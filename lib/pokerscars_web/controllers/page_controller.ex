defmodule PokerscarsWeb.PageController do
  use PokerscarsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
