-- Autenticação do broker: "esta credencial existe e ainda vale?"
--
-- Mesmo contrato do `acl.sql`: este texto é executado no EMQX e é o mesmo que
-- `backend/tests/mqtt-sql.test.ts` roda contra um Postgres real.
--
-- `${username}` é o id da credencial (`mqtt_sessions.id`). O EMQX calcula o
-- SHA-256 em hex da senha apresentada — configurado com
-- `password_hash_algorithm = {name = sha256, encode_type = hex}` — e compara com a
-- coluna `password_hash`. A senha em texto puro nunca é armazenada nem trafega para
-- fora do CONNECT cifrado por TLS.
--
-- Não há sal: a senha já é 256 bits de aleatoriedade de alto alcance, gerada pelo
-- CSPRNG do servidor, então o papel do sal (defender dicionário e colisões de
-- tabela arco-íris) não existe aqui. A coluna vazia volta só porque o formato do
-- EMQX a espera.
--
-- `expires_at` é o que dá dente ao "curta duração": com a sessão expirada, a linha
-- deixa de voltar e o CONNECT é recusado, mesmo sem ninguém ter apagado nada.

SELECT
  s.password_hash AS password_hash,
  ''              AS salt,
  s.expires_at    AS expire_at
FROM mqtt_sessions s
WHERE s.id = ${username}
  AND s.expires_at > now();
