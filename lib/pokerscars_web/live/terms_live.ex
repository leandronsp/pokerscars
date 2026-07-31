defmodule PokerscarsWeb.TermsLive do
  @moduledoc """
  The hosted instance's terms of use, in plain words: play chips carry no
  monetary value, the tab is a scoreboard, the platform never touches money.
  """

  use PokerscarsWeb, :live_view

  @impl Phoenix.LiveView
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: gettext("termos de uso") <> " · pokerscars")}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} currency={@currency}>
      <article class="pk-terms">
        <h1>{gettext("termos de uso")}</h1>
        <p class="pk-terms-updated">{gettext("última atualização: julho de 2026")}</p>

        <p>
          {gettext(
            "o pokerscars é uma plataforma recreativa de poker entre amigos. ao usar a instância oficial, você concorda com estes termos."
          )}
        </p>

        <h2>{gettext("fichas sem valor real")}</h2>
        <p>
          {gettext(
            "as fichas do jogo são pontos virtuais, sem qualquer valor monetário. elas não podem ser compradas, vendidas, trocadas nem resgatadas por dinheiro, dentro ou fora da plataforma. não existe compra de fichas, não existe prêmio em dinheiro e não existe rake: ninguém aqui lucra com o resultado das mãos."
          )}
        </p>

        <h2>{gettext("a comanda é um placar")}</h2>
        <p>
          {gettext(
            "a comanda de cada mesa registra compras e saques de fichas para o grupo saber o saldo da noite. a plataforma não processa pagamentos, não intermedeia apostas e não participa de acerto nenhum entre jogadores. se o seu grupo resolve dar valor às fichas, isso é um acordo privado de vocês, feito fora da plataforma, sob responsabilidade exclusiva de quem participa e sujeito às leis do lugar onde vocês estão."
          )}
        </p>

        <h2>{gettext("maiores de 18")}</h2>
        <p>
          {gettext(
            "o pokerscars é para maiores de 18 anos. se essa não é a maioridade onde você mora, vale a de lá."
          )}
        </p>

        <h2>{gettext("sem cadastro, poucos dados")}</h2>
        <p>
          {gettext(
            "não há cadastro. sua identidade aqui é um cookie de sessão anônimo e o apelido que você escolhe ao sentar. guardamos o mínimo para a mesa funcionar: a configuração das mesas abertas e suas comandas. chat e histórico de mãos são transitórios e somem com a mesa."
          )}
        </p>

        <h2>{gettext("na mesa")}</h2>
        <p>
          {gettext(
            "jogue limpo. não use a plataforma para operar apostas com dinheiro real, para assediar outras pessoas nem para qualquer atividade ilegal. quem cria a mesa pode encerrá-la a qualquer momento, e a casa pode encerrar mesas que violem estes termos."
          )}
        </p>

        <h2>{gettext("software livre")}</h2>
        <p>
          {gettext(
            "o código do pokerscars é livre, sob a licença AGPL-3.0, e você pode hospedar a sua própria instância nos termos dela. a marca pokerscars não faz parte da licença. estes termos valem para a instância oficial; outras instâncias respondem pelos seus próprios termos."
          )}
          <a href="https://github.com/leandronsp/pokerscars">{gettext("o código está no GitHub")}</a>.
        </p>

        <h2>{gettext("sem garantias")}</h2>
        <p>
          {gettext(
            "o serviço é oferecido como está, sem garantia de disponibilidade nem de continuidade. ele pode mudar, pausar ou encerrar, e mesas e comandas podem se perder. na extensão máxima permitida em lei, não nos responsabilizamos por danos decorrentes do uso da plataforma."
          )}
        </p>

        <h2>{gettext("mudanças")}</h2>
        <p>
          {gettext("estes termos podem mudar. a versão vigente estará sempre nesta página.")}
        </p>

        <h2>{gettext("contato")}</h2>
        <p>
          {gettext("dúvida ou problema?")}
          <a href="https://github.com/leandronsp/pokerscars/issues">
            {gettext("abra uma issue no GitHub")}
          </a>.
        </p>

        <p class="pk-terms-back">
          <.link navigate={~p"/"}>{gettext("← voltar pro salão")}</.link>
        </p>
      </article>
    </Layouts.app>
    """
  end
end
