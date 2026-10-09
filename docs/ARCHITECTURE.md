# Arquitetura

## Fluxo

`Provedor → conexão local por perfil → AccountStore → snapshot → WidgetKit`

O menu e o painel opcional compartilham o AccountStore. A extensão não executa login: lê somente o snapshot local. Nenhuma integração com portal está incluída.

## Dados locais

- Preferências: UserDefaults do bundle `app.quotaglass.mac`.
- Perfis Codex: Application Support/QuotaGlass/accounts, separados por UUID; credenciais gerenciadas pelo CLI com armazenamento keyring.
- Claude: WKWebsiteDataStore persistente separado por UUID.
- Widget: Application Support/QuotaGlass/widget.json, com cotas, rótulos e escolhas de exibição; não contém credenciais.

O build ad hoc autoriza a extensão a ler apenas esse arquivo por uma exceção de sandbox específica do usuário. Para distribuir binários assinados, será necessário substituir esse mecanismo por App Groups e configurar assinatura/notarização.

## Fundo translúcido no macOS 27

O script `scripts/prepare-widgetkit-overlay.py` lê a interface pública e os símbolos do SDK local; gera um overlay ignorado pelo Git e declara a interface privada `WidgetBackgroundStyle`/`preferredBackgroundStyle`. A extensão solicita `.blur`, mantém o container transparente e adapta anéis/ícones ao widgetRenderingMode.

O script exige SDK 27 e verifica os símbolos esperados antes da compilação. Não altera SDK, frameworks, processos ou widget Bateria do sistema. O overlay gerado e arquivos do SDK não são distribuídos.

## Contagens e falhas

Codex fornece contagem somente quando `rateLimitResetCredits.availableCount` existe e é válido. Claude não fornece contagem nesta integração. Valor ausente permanece ausente; porcentagem desconhecida aparece como travessão.

Claude mantém intervalo mínimo de cinco minutos e conserva a última leitura em caso de limitação. O indicador de atualização é do ciclo do aplicativo; pode incluir dados em cache. WidgetKit decide a frequência real de renderização.

## Evidência desta versão

- Build de host e extensão concluído com SDK macOS 27.
- Revisão estática das conexões e seleção de arquivos públicos.
- Não foi executada verificação autenticada dos provedores na versão independente.
