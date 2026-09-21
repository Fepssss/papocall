-- Autorização do broker: "esta credencial pode tocar este tópico?"
--
-- Este arquivo é a regra executada no EMQX, e é o mesmo texto que o teste
-- `backend/tests/mqtt-sql.test.ts` roda contra um Postgres de verdade. Não é cópia
-- do que a aplicação sabe: é a fonte, lida pelo broker. O motivo de existir um teste
-- em cima dele é que a tabela de verdade mora em outro lugar
-- (`backend/src/utils/mqttTopics.ts`), e regra de segurança duplicada à mão diverge
-- em silêncio — com o broker negando o que a aplicação acha permitido, ou o
-- contrário. Foi assim que este arquivo foi pego: a primeira versão autorizava
-- `.../inboxVIZINHO` como se estivesse dentro de `.../inbox`.
--
-- `${username}` aqui é o identificador da CREDENCIAL (`mqtt_sessions.id`), não o id
-- do usuário: uma conta pode ter várias credenciais vivas ao mesmo tempo (vários
-- aparelhos abertos), e o nome de login no broker precisa ser único por credencial.
--
-- Os `${...}` são a sintaxe de placeholder do data source do EMQX; o teste os
-- converte para parâmetros posicionais do Postgres antes de executar.
--
-- Colunas esperadas pelo EMQX: `permission`, `action` e `topic`. Uma linha
-- retornada autoriza; nenhuma linha deixa o `no_match` do broker decidir, que é
-- `deny` — o padrão fechado desta migração.

WITH viva AS (
  -- Um morto aqui não autoriza nada. É o que faz "sair de todas as sessões" valer
  -- também para a próxima assinatura de quem ficou com o aplicativo aberto: sem
  -- este CTE, a revogação só apareceria no reconexão seguinte.
  SELECT s.user_id
  FROM mqtt_sessions s
  WHERE s.id = ${username}
    AND s.expires_at > now()
)
-- 1. Tudo abaixo de um prefixo próprio do usuário: a caixa de entrada dele (com o
--    curinga de reconexão) e a própria presença.
--
--    A fronteira é o separador de nível, não o começo do texto: `starts_with`
--    sozinho deixaria `.../inboxVIZINHO` passar como se estivesse dentro de
--    `.../inbox`.
SELECT
  ${topic}   AS topic,
  ${action}  AS action,
  'allow'    AS permission
FROM viva, mqtt_grants g
WHERE g.user_id = viva.user_id
  AND (${topic} = g.topic_prefix OR starts_with(${topic}, g.topic_prefix || '/'))

UNION ALL

-- 2. Escrever num compartimento da caixa de entrada de OUTRA pessoa: é o caminho
--    de uma mensagem direta e de um pedido de amizade para quem ainda não é
--    contato. Só um nível abaixo do `inbox`, nunca no nó dele, e nunca para ler —
--    assinar a caixa alheia não tem ramo aqui, então cai no deny.
SELECT
  ${topic}    AS topic,
  'publish'   AS action,
  'allow'     AS permission
FROM viva
WHERE ${action} = 'publish'
  AND ${topic} ~ '^papocall/v2/u/[0-9a-f]{32}/inbox/[^/]+$'

UNION ALL

-- 3. Presença de outra pessoa, para ler: a lista de amigos depende disto, e o
--    conteúdo é cifrado de qualquer jeito. Publicar na presença alheia não tem
--    ramo aqui — seria o jeito mais barato de fingir que alguém está onde não está.
SELECT
  ${topic}     AS topic,
  'subscribe'  AS action,
  'allow'      AS permission
FROM viva
WHERE ${action} = 'subscribe'
  AND ${topic} ~ '^papocall/v2/u/[0-9a-f]{32}/presence$';
