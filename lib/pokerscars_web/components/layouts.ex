defmodule PokerscarsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PokerscarsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :locale, :string, default: "pt_BR"
  attr :currency, :string, default: "BRL"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="pk-topbar">
      <a href="/" class="pk-topbar-brand">♠ pokerscars</a>
      <span class="pk-topbar-spacer"></span>
      <details class="pk-cheat" id="pk-cheat" phx-update="ignore">
        <summary aria-label={gettext("colinha de mãos")} title={gettext("colinha de mãos")}>
          <span class="pk-cheat-fan" aria-hidden="true">
            <span class="pk-mini-card">A♠</span>
            <span class="pk-mini-card pk-mini-card--red">K♥</span>
          </span>
          <span class="pk-cheat-word">{gettext("mãos")}</span>
        </summary>
        <div class="pk-cheat-panel">
          <h3 class="pk-cheat-title">{gettext("da mais forte pra mais fraca")}</h3>
          <ol class="pk-cheat-list">
            <li :for={{category, example} <- cheat_rows()}>
              <strong>{PokerscarsWeb.TableComponents.hand_name(category)}</strong>
              <span class="pk-cheat-ex">
                <span
                  :for={card <- String.split(example, " ")}
                  class={["pk-mini-card", red_suit?(card) && "pk-mini-card--red"]}
                >
                  {card}
                </span>
              </span>
            </li>
          </ol>
          <details class="pk-cheat-more">
            <summary>{gettext("como ler sua mão")}</summary>
            <ul class="pk-cheat-tips">
              <li>
                {gettext("sua mão final são as melhores 5 cartas entre as suas 2 e as 5 da mesa.")}
              </li>
              <li>
                {gettext(
                  "mesma categoria? desempata a carta mais alta (depois a segunda, e assim vai)."
                )}
              </li>
              <li>
                {gettext(
                  "o chip \"sua mão\" embaixo do feltro já diz o que você tem a cada carta que vira."
                )}
              </li>
            </ul>
          </details>
        </div>
      </details>
      <nav class="pk-topbar-prefs">
        <a href="/prefs?locale=pt_BR" class={@locale == "pt_BR" && "pk-pref-active"}>PT</a>
        <a href="/prefs?locale=en" class={@locale == "en" && "pk-pref-active"}>EN</a>
        <span class="pk-topbar-sep" aria-hidden="true"></span>
        <a href="/prefs?currency=BRL" class={@currency == "BRL" && "pk-pref-active"}>R$</a>
        <a href="/prefs?currency=USD" class={@currency == "USD" && "pk-pref-active"}>$</a>
        <a href="/prefs?currency=EUR" class={@currency == "EUR" && "pk-pref-active"}>€</a>
      </nav>
    </header>

    <main class="pk-main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :locale, :string, default: "pt_BR"
  attr :currency, :string, default: "BRL"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  defp red_suit?(card), do: String.contains?(card, "♥") or String.contains?(card, "♦")

  # Strongest to weakest, names straight from the table's own vocabulary.
  defp cheat_rows do
    [
      {:straight_flush, "9♥ 8♥ 7♥ 6♥ 5♥"},
      {:four_of_a_kind, "Q♠ Q♥ Q♦ Q♣ 7♦"},
      {:full_house, "K♠ K♥ K♦ 4♠ 4♣"},
      {:flush, "A♣ J♣ 8♣ 6♣ 2♣"},
      {:straight, "8♠ 7♥ 6♦ 5♣ 4♠"},
      {:three_of_a_kind, "7♠ 7♥ 7♦ K♣ 2♥"},
      {:two_pair, "J♠ J♦ 9♥ 9♣ A♠"},
      {:pair, "10♠ 10♥ A♦ 7♣ 3♠"},
      {:high_card, "A♠ Q♦ 9♥ 6♣ 3♦"}
    ]
  end
end
