# XAUUSD MT5 Expert Advisors

Coleção de Expert Advisors (EAs) para MetaTrader 5 voltados ao par **XAUUSD** (Ouro), com foco em conta demo/testes e controle de risco.

## Arquivos

| Arquivo | Descrição |
|---|---|
| `XAUUSD_Trend_ATR_v11_UltraConservador.mq5` | Versão ultra conservadora (M15 + filtro macro H1). Entradas por cruzamento EMA 9/21 com confirmação da EMA 100 no H1. **Sem SL/TP automático** — fechamento 100% manual. Limite de 3 operações por dia e filtro de spread. |

## Requisitos

- [MetaTrader 5](https://www.metatrader5.com/) (build recente)
- Conta **demo** recomendada para testes
- Símbolo `XAUUSD` disponível na corretora

## Instalação

1. Abra o MetaTrader 5.
2. No menu, vá em **Arquivo → Abrir Pasta de Dados**.
3. Navegue até `MQL5\Experts\`.
4. Copie o arquivo `.mq5` desejado para essa pasta.
5. Abra o **MetaEditor** (F4 no MT5) e compile o arquivo (F7). Deve resultar em `0 error(s)`.
6. Volte ao MT5, abra um gráfico `XAUUSD` no timeframe recomendado pelo EA.
7. No **Navegador** (Ctrl+N) → **Consultores Especialistas**, arraste o EA para o gráfico.
8. Na aba **Comum**, marque **Permitir negociação algorítmica/automática**.
9. Ajuste os parâmetros na aba **Entradas** se necessário e clique em **OK**.
10. Verifique se o botão **Algo Trading** está verde e se o ícone do EA aparece no canto do gráfico.

## Avisos

- **Use somente em conta demo** até validar completamente a estratégia.
- Resultados passados não garantem resultados futuros.
- Revise sempre os parâmetros de risco (lote, spread máximo, limite diário) antes de executar.
- O EA `v11_UltraConservador` **não fecha posições automaticamente** — o gerenciamento de saída é manual.

## Licença

Uso pessoal/educacional. Sem garantias.
