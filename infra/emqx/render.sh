#!/usr/bin/env bash
# Monta `etc/emqx.conf` a partir do template + das duas consultas SQL + do banco.
#
# O arquivo gerado contém a senha do banco, por isso nasce dentro de `etc/`, que
# está no .gitignore: o que se versiona aqui é a receita, nunca o resultado.
set -euo pipefail
cd "$(dirname "$0")"

: "${BANCO_HOST:?defina BANCO_HOST (ex.: banco.neon.tech)}"
: "${BANCO_PORT:=5432}"
: "${BANCO_USUARIO:?defina BANCO_USUARIO}"
: "${BANCO_SENHA:?defina BANCO_SENHA}"
: "${BANCO_NOME:?defina BANCO_NOME}"

# `&` no lado da substituição do sed significa "o texto casado inteiro", e `|` é o
# delimitador. Uma senha de banco com qualquer um dos dois sairia daqui truncada ou
# com o valor trocado, e o erro só apareceria no primeiro CONNECT recusado pelo
# broker. Escapa antes.
esc() { local v="$1"; v="${v//\\/\\\\}"; v="${v//&/\\&}"; v="${v//|/\\|}"; printf '%s' "$v"; }

BANCO_HOST=$(esc "$BANCO_HOST")
BANCO_PORT=$(esc "$BANCO_PORT")
BANCO_USUARIO=$(esc "$BANCO_USUARIO")
BANCO_SENHA=$(esc "$BANCO_SENHA")
BANCO_NOME=$(esc "$BANCO_NOME")

mkdir -p etc

sed \
  -e "s|__DB_HOST__|$BANCO_HOST|g" \
  -e "s|__DB_PORT__|$BANCO_PORT|g" \
  -e "s|__DB_USER__|$BANCO_USUARIO|g" \
  -e "s|__DB_PASS__|$BANCO_SENHA|g" \
  -e "s|__DB_NAME__|$BANCO_NOME|g" \
  -e '/__AUTHN_SQL__/r authn.sql' -e '/__AUTHN_SQL__/d' \
  emqx.conf.template \
  | sed -e '/__ACL_SQL__/r acl.sql' -e '/__ACL_SQL__/d' \
  > etc/emqx.conf

# O teste do CI lê exatamente estes dois arquivos. Se algum marcador sobrou, a
# regra não foi injetada e o broker subiria com uma consulta incompleta — melhor
# parar aqui do que descobrir no primeiro CONNECT negado.
if grep -q '__\(AUTHN\|ACL\)_SQL__\|__DB_' etc/emqx.conf; then
  echo "sobrou marcador em etc/emqx.conf; nada injetado" >&2
  exit 1
fi

echo "etc/emqx.conf gerado ($(wc -l < etc/emqx.conf) linhas)."
echo "confira antes de subir:  docker run --rm -v \"\$PWD/etc/emqx.conf:/opt/emqx/etc/emqx.conf:ro\" emqx/emqx:5.8.6 emqx check /opt/emqx/etc/emqx.conf"
