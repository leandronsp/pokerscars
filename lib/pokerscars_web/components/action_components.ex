defmodule PokerscarsWeb.ActionComponents do
  @moduledoc """
  The action bar. Raise presets sit right on the bar — one tap commits the
  raise (all-in alone asks for a second tap). The slider is the optional
  "outro valor" path. The bar zone has a fixed height upstream so swapping
  states never moves the table.
  """

  use Phoenix.Component
  use Gettext, backend: PokerscarsWeb.Gettext

  import PokerscarsWeb.Money

  attr :actions, :list, required: true
  attr :presets, :list, required: true, doc: "[{label, amount}] ready-to-tap raises"
  attr :all_in_armed?, :boolean, default: false

  @spec action_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def action_bar(assigns) do
    assigns =
      assigns
      |> assign(:call, Enum.find(assigns.actions, &match?({:call, _amount}, &1)))
      |> assign(:check?, :check in assigns.actions)
      |> assign(:raise, Enum.find(assigns.actions, &match?({:raise_to, _min, _max}, &1)))

    ~H"""
    <div class="pk-actions-stack" id="pk-actions">
      <div :if={@raise} class="pk-sizing-presets">
        <%= for {label, amount, all_in?} <- @presets do %>
          <button
            :if={not all_in?}
            class="pk-chipbtn"
            phx-click="preset_raise"
            phx-value-amount={amount}
          >
            <span class="pk-chipbtn-label">{label}</span>
            <span class="pk-chipbtn-amount">{chips(amount)}</span>
          </button>
          <button
            :if={all_in?}
            class={["pk-chipbtn pk-chipbtn--allin", @all_in_armed? && "pk-chipbtn--armed"]}
            phx-click={if @all_in_armed?, do: "preset_raise", else: "arm_all_in"}
            phx-value-amount={amount}
          >
            <span class="pk-chipbtn-label">
              {if @all_in_armed?, do: gettext("confirma?"), else: gettext("all-in")}
            </span>
            <span class="pk-chipbtn-amount">{chips(amount)}</span>
          </button>
        <% end %>
      </div>

      <div class="pk-actions">
        <button :if={@call} class="pk-btn pk-btn--fold" phx-click="act" phx-value-action="fold">
          {gettext("desistir")}
        </button>
        <span :if={@check?} class="pk-actions-spacer" aria-hidden="true"></span>

        <button :if={@check?} class="pk-btn pk-btn--call" phx-click="act" phx-value-action="check">
          {gettext("passar")}
        </button>
        <button :if={@call} class="pk-btn pk-btn--call" phx-click="act" phx-value-action="call">
          {gettext("pagar")} {@call |> elem(1) |> chips()}
        </button>

        <button :if={@raise} class="pk-btn pk-btn--raise" phx-click="open_sizing">
          {gettext("outro valor")} ▸
        </button>
        <span :if={@raise == nil} class="pk-actions-spacer" aria-hidden="true"></span>
      </div>
    </div>
    """
  end

  attr :bounds, :any, required: true, doc: "{:raise_to, min, max}"
  attr :raise_to, :integer, required: true
  attr :all_in_armed?, :boolean, default: false

  @spec sizing_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def sizing_panel(assigns) do
    {:raise_to, min, max} = assigns.bounds
    assigns = assign(assigns, min: min, max: max, all_in?: assigns.raise_to == max)

    ~H"""
    <div class="pk-sizing" id="pk-sizing">
      <form id="pk-raise-form" phx-change="set_raise">
        <input
          type="range"
          name="value"
          class="pk-slider"
          min={@min}
          max={@max}
          value={@raise_to}
          step="1"
          phx-throttle="150"
        />
      </form>

      <div class="pk-sizing-commit">
        <button class="pk-btn pk-btn--ghost" phx-click="close_sizing">← {gettext("voltar")}</button>
        <button
          class={["pk-btn pk-btn--raise", @all_in_armed? && "pk-btn--danger"]}
          phx-click="confirm_raise"
        >
          <%= cond do %>
            <% @all_in_armed? -> %>
              {gettext("confirmar all-in?")}
            <% @all_in? -> %>
              {gettext("all-in")} {chips(@raise_to)}
            <% true -> %>
              {gettext("aumentar para")} {chips(@raise_to)}
          <% end %>
        </button>
      </div>
    </div>
    """
  end
end
