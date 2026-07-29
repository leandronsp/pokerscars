defmodule PokerscarsWeb.ActionComponents do
  @moduledoc """
  The action bar: three fixed slots so muscle memory holds, sizing as a
  second step in the same footprint (the misclick guard), fold hidden when
  checking is free. Only all-in asks for confirmation.
  """

  use Phoenix.Component
  use Gettext, backend: PokerscarsWeb.Gettext

  import PokerscarsWeb.Money

  attr :actions, :list, required: true

  @spec action_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def action_bar(assigns) do
    assigns =
      assigns
      |> assign(:call, Enum.find(assigns.actions, &match?({:call, _amount}, &1)))
      |> assign(:check?, :check in assigns.actions)
      |> assign(:raise, Enum.find(assigns.actions, &match?({:raise_to, _min, _max}, &1)))

    ~H"""
    <div class="pk-actions" id="pk-actions">
      <button :if={@call} class="pk-btn pk-btn--fold" phx-click="act" phx-value-action="fold">
        {gettext("fold")}
      </button>
      <span :if={@check?} class="pk-actions-spacer" aria-hidden="true"></span>

      <button :if={@check?} class="pk-btn pk-btn--call" phx-click="act" phx-value-action="check">
        {gettext("check")}
      </button>
      <button :if={@call} class="pk-btn pk-btn--call" phx-click="act" phx-value-action="call">
        {gettext("pagar")} {@call |> elem(1) |> chips()}
      </button>

      <button :if={@raise} class="pk-btn pk-btn--raise" phx-click="open_sizing">
        {if @check?, do: gettext("apostar"), else: gettext("aumentar")} ▸
      </button>
      <span :if={@raise == nil} class="pk-actions-spacer" aria-hidden="true"></span>
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
      <div class="pk-sizing-presets">
        <button class="pk-chipbtn" phx-click="preset" phx-value-kind="half">1/2</button>
        <button class="pk-chipbtn" phx-click="preset" phx-value-kind="two_thirds">2/3</button>
        <button class="pk-chipbtn" phx-click="preset" phx-value-kind="pot">{gettext("pote")}</button>
        <button class="pk-chipbtn pk-chipbtn--allin" phx-click="preset" phx-value-kind="all_in">
          {gettext("all-in")}
        </button>
      </div>

      <form phx-change="set_raise">
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
